import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesh_rescue/crypto/device_identity_store.dart';
import 'package:mesh_rescue/crypto/signer.dart';
import 'package:mesh_rescue/crypto/trust_service.dart';
import 'package:mesh_rescue/data/message_store.dart';
import 'package:mesh_rescue/engine/clock.dart';
import 'package:mesh_rescue/engine/mesh_engine.dart';
import 'package:mesh_rescue/engine/models/enums.dart';
import 'package:mesh_rescue/engine/models/payloads.dart';
import 'package:mesh_rescue/services/permission_service.dart';
import 'package:mesh_rescue/services/platform_checks.dart';
import 'package:mesh_rescue/transport/nearby_transport.dart';

enum MeshBootStatus {
  checking,
  unsupportedDevice,
  needsPermissions,
  ready,
  error,
}

class MeshUiState {
  final MeshBootStatus bootStatus;
  final PlayServicesStatus? playServicesStatus;
  final MeshPermissionsState? permissionsState;
  final String? deviceId;
  final bool isAdvertising;
  final bool isDiscovering;
  final List<NearbyPeerTelemetry> peers;
  final List<StoredMessage> messages;
  final Map<DropReason, int> dropCounts;
  final int relayedCount;
  final List<String> logs;
  final String? errorMessage;

  const MeshUiState({
    required this.bootStatus,
    this.playServicesStatus,
    this.permissionsState,
    this.deviceId,
    this.isAdvertising = false,
    this.isDiscovering = false,
    this.peers = const <NearbyPeerTelemetry>[],
    this.messages = const <StoredMessage>[],
    this.dropCounts = const <DropReason, int>{},
    this.relayedCount = 0,
    this.logs = const <String>[],
    this.errorMessage,
  });

  MeshUiState copyWith({
    MeshBootStatus? bootStatus,
    PlayServicesStatus? playServicesStatus,
    MeshPermissionsState? permissionsState,
    String? deviceId,
    bool? isAdvertising,
    bool? isDiscovering,
    List<NearbyPeerTelemetry>? peers,
    List<StoredMessage>? messages,
    Map<DropReason, int>? dropCounts,
    int? relayedCount,
    List<String>? logs,
    String? errorMessage,
  }) {
    return MeshUiState(
      bootStatus: bootStatus ?? this.bootStatus,
      playServicesStatus: playServicesStatus ?? this.playServicesStatus,
      permissionsState: permissionsState ?? this.permissionsState,
      deviceId: deviceId ?? this.deviceId,
      isAdvertising: isAdvertising ?? this.isAdvertising,
      isDiscovering: isDiscovering ?? this.isDiscovering,
      peers: peers ?? this.peers,
      messages: messages ?? this.messages,
      dropCounts: dropCounts ?? this.dropCounts,
      relayedCount: relayedCount ?? this.relayedCount,
      logs: logs ?? this.logs,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class MeshController extends Notifier<MeshUiState> {
  static const int _maxLogLines = 120;

  late final PlatformChecks _platformChecks;
  late final PermissionService _permissionService;
  late final DeviceIdentityStore _identityStore;

  final List<String> _logBuffer = <String>[];
  MessageStore? _store;
  NearbyTransport? _transport;
  MeshEngine? _engine;
  Timer? _tickTimer;
  StreamSubscription<StoredMessage>? _acceptedSub;
  StreamSubscription<DropEvent>? _dropSub;
  bool _initialized = false;

  @override
  MeshUiState build() {
    _platformChecks = PlatformChecks();
    _permissionService = PermissionService(platformChecks: _platformChecks);
    _identityStore = DeviceIdentityStore();

    ref.onDispose(() {
      unawaited(_shutdownEngine());
    });

    Future.microtask(initialize);
    return const MeshUiState(bootStatus: MeshBootStatus.checking);
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await recheckAndStart();
  }

  Future<void> recheckAndStart() async {
    state = state.copyWith(bootStatus: MeshBootStatus.checking);
    final gms = await _platformChecks.checkGooglePlayServices();
    if (!gms.isAvailable) {
      _appendLog('[MESH] Unsupported device: ${gms.statusMessage} (${gms.statusCode})');
      state = state.copyWith(
        bootStatus: MeshBootStatus.unsupportedDevice,
        playServicesStatus: gms,
      );
      return;
    }

    final perms = await _permissionService.checkCurrent();
    if (!perms.isReady) {
      _appendLog(
        '[MESH] Permissions/Location pending: granted=${perms.allPermissionsGranted} locEnabled=${perms.locationServiceEnabled}',
      );
      state = state.copyWith(
        bootStatus: MeshBootStatus.needsPermissions,
        playServicesStatus: gms,
        permissionsState: perms,
      );
      return;
    }

    await _startMeshStack(gms, perms);
  }

  Future<void> requestPermissionsAndStart() async {
    final gms = state.playServicesStatus ??
        await _platformChecks.checkGooglePlayServices();
    if (!gms.isAvailable) {
      state = state.copyWith(
        bootStatus: MeshBootStatus.unsupportedDevice,
        playServicesStatus: gms,
      );
      return;
    }

    final perms = await _permissionService.requestAll();
    if (!perms.isReady) {
      state = state.copyWith(
        bootStatus: MeshBootStatus.needsPermissions,
        playServicesStatus: gms,
        permissionsState: perms,
      );
      return;
    }

    await _startMeshStack(gms, perms);
  }

  Future<void> openLocationSettings() => _permissionService.openLocationSettings();

  Future<void> openAppSettings() =>
      _permissionService.openAppPermissionsSettings();

  Future<void> _startMeshStack(
    PlayServicesStatus gms,
    MeshPermissionsState perms,
  ) async {
    try {
      await _shutdownEngine();
      final trustJson =
          await rootBundle.loadString('assets/trusted_responders.json');
      final trustService = TrustService.fromJsonString(trustJson);
      final identity = await _identityStore.loadOrCreate();
      final store = InMemoryMessageStore();
      const clock = SystemClock();
      final transport = NearbyTransport(
        deviceId: identity.origin,
        clock: clock,
        logSink: _appendLog,
      );
      final engine = MeshEngine(
        transport: transport,
        store: store,
        signer: Ed25519Signer(),
        identity: identity,
        trustService: trustService,
        clock: clock,
        minSendSpacingMillis: 40,
      );

      _store = store;
      _transport = transport;
      _engine = engine;

      _acceptedSub = engine.onMessageAccepted.listen((msg) {
        _appendLog(
          '[MESH] Accepted ${msg.type.wireName} id=${msg.id.substring(0, 8)} '
          'from=${msg.envelope.origin} hops=${msg.envelope.hops} ttl=${msg.envelope.ttl}',
        );
        unawaited(_refreshSnapshot());
      });
      _dropSub = engine.onDrop.listen((drop) {
        _appendLog(
          '[MESH] Drop ${drop.reason.code} peer=${drop.peerId}: ${drop.detail}',
        );
        unawaited(_refreshSnapshot());
      });

      await engine.start();
      _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        unawaited(_onTick());
      });

      state = state.copyWith(
        bootStatus: MeshBootStatus.ready,
        playServicesStatus: gms,
        permissionsState: perms,
        deviceId: identity.origin,
        isAdvertising: transport.isAdvertising,
        isDiscovering: transport.isDiscovering,
        peers: transport.peerTelemetry,
        logs: List<String>.unmodifiable(_logBuffer),
      );
      await _refreshSnapshot();
    } catch (e) {
      _appendLog('[MESH] Startup error: $e');
      state = state.copyWith(
        bootStatus: MeshBootStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> restartRadio() async {
    final perms = await _permissionService.checkCurrent();
    final gms = await _platformChecks.checkGooglePlayServices();
    if (!gms.isAvailable || !perms.isReady) {
      await recheckAndStart();
      return;
    }
    await _startMeshStack(gms, perms);
  }

  Future<void> sendTestMessage({String note = 'Mesh relay ping'}) async {
    final engine = _engine;
    if (engine == null) return;
    final msg = await engine.publishHazard(
      payload: HazardPayload(
        kind: HazardKind.other,
        severity: 1,
        note: '$note from ${engine.identity.origin}',
      ),
      lat: 0.0,
      lng: 0.0,
    );
    _appendLog(
      '[MESH] Published test msg id=${msg.id.substring(0, 8)} origin=${msg.envelope.origin}',
    );
    await _refreshSnapshot();
  }

  Future<void> _onTick() async {
    final engine = _engine;
    if (engine == null) return;
    await engine.tick();
    await _refreshSnapshot();
  }

  Future<void> _refreshSnapshot() async {
    final store = _store;
    final transport = _transport;
    final engine = _engine;
    if (store == null || transport == null || engine == null) return;

    final all = await store.getAllMessages();
    final sorted = List<StoredMessage>.from(all)
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));

    state = state.copyWith(
      isAdvertising: transport.isAdvertising,
      isDiscovering: transport.isDiscovering,
      peers: transport.peerTelemetry,
      messages: List<StoredMessage>.unmodifiable(sorted),
      dropCounts: engine.dropCounts,
      relayedCount: engine.relayedCount,
      logs: List<String>.unmodifiable(_logBuffer),
    );
  }

  void _appendLog(String line) {
    debugPrint(line);
    _logBuffer.add(line);
    if (_logBuffer.length > _maxLogLines) {
      _logBuffer.removeAt(0);
    }
  }

  Future<void> _shutdownEngine() async {
    _tickTimer?.cancel();
    _tickTimer = null;
    await _acceptedSub?.cancel();
    await _dropSub?.cancel();
    _acceptedSub = null;
    _dropSub = null;
    await _engine?.dispose();
    await _transport?.dispose();
    _engine = null;
    _transport = null;
    _store = null;
  }
}

