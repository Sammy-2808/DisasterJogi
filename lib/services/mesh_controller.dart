import 'dart:async';
import 'dart:math';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesh_rescue/crypto/demo_responder_key.dart';
import 'package:mesh_rescue/crypto/device_identity_store.dart';
import 'package:mesh_rescue/crypto/signer.dart';
import 'package:mesh_rescue/crypto/trust_service.dart';
import 'package:mesh_rescue/data/db.dart';
import 'package:mesh_rescue/data/drift_message_store.dart';
import 'package:mesh_rescue/data/message_store.dart';
import 'package:mesh_rescue/domain/geo.dart';
import 'package:mesh_rescue/domain/hazard_cluster.dart';
import 'package:mesh_rescue/domain/shelter_logic.dart';
import 'package:mesh_rescue/domain/sos_state.dart';
import 'package:mesh_rescue/engine/clock.dart';
import 'package:mesh_rescue/engine/mesh_engine.dart';
import 'package:mesh_rescue/engine/models/envelope.dart';
import 'package:mesh_rescue/engine/models/enums.dart';
import 'package:mesh_rescue/engine/models/frame.dart';
import 'package:mesh_rescue/engine/models/payloads.dart';
import 'package:mesh_rescue/services/expiry_service.dart';
import 'package:mesh_rescue/services/location_service.dart';
import 'package:mesh_rescue/services/permission_service.dart';
import 'package:mesh_rescue/services/platform_checks.dart';
import 'package:mesh_rescue/transport/nearby_transport.dart';
import 'package:uuid/uuid.dart';

enum MeshBootStatus {
  checking,
  unsupportedDevice,
  onboarding,
  needsPermissions,
  ready,
  error,
}

class MeshAlertBanner {
  final String title;
  final String body;
  final bool isSos;
  final int timestampSec;

  const MeshAlertBanner({
    required this.title,
    required this.body,
    required this.isSos,
    required this.timestampSec,
  });
}

class MeshUiState {
  final MeshBootStatus bootStatus;
  final PlayServicesStatus? playServicesStatus;
  final MeshPermissionsState? permissionsState;
  final String? deviceId;
  final bool isAdvertising;
  final bool isDiscovering;
  final bool batterySaver;
  final GeoFix? locationFix;
  final IdentityKeyPair? responderIdentity;
  final TrustService trustService;
  final List<NearbyPeerTelemetry> peers;
  final List<StoredMessage> messages;
  final Map<DropReason, int> dropCounts;
  final int relayedCount;
  final List<String> logs;
  final MeshAlertBanner? alertBanner;
  final String? errorMessage;

  const MeshUiState({
    required this.bootStatus,
    this.playServicesStatus,
    this.permissionsState,
    this.deviceId,
    this.isAdvertising = false,
    this.isDiscovering = false,
    this.batterySaver = false,
    this.locationFix,
    this.responderIdentity,
    TrustService? trustService,
    this.peers = const <NearbyPeerTelemetry>[],
    this.messages = const <StoredMessage>[],
    this.dropCounts = const <DropReason, int>{},
    this.relayedCount = 0,
    this.logs = const <String>[],
    this.alertBanner,
    this.errorMessage,
  }) : trustService = trustService ?? const _EmptyTrust();

  bool get isResponderUnlocked => responderIdentity != null;

  List<SosDerivation> sosAlerts({int? nowSeconds}) {
    final now = nowSeconds ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    final sosMessages =
        messages.where((m) => m.type == MessageType.sos).toList();
    final acks = messages.where((m) => m.type == MessageType.ack).toList();

    final list = sosMessages
        .map(
          (sos) => deriveSosState(
            sos: sos,
            candidateAcks: acks.where((a) => a.envelope.refId == sos.id),
            trustService: trustService,
            nowSeconds: now,
          ),
        )
        .toList();

    list.sort((a, b) {
      final localCmp = (b.sos.isLocal ? 1 : 0).compareTo(a.sos.isLocal ? 1 : 0);
      if (localCmp != 0) return localCmp;
      final activeCmp = (a.status == SosStatus.active ? 0 : 1)
          .compareTo(b.status == SosStatus.active ? 0 : 1);
      if (activeCmp != 0) return activeCmp;
      return b.sos.receivedAt.compareTo(a.sos.receivedAt);
    });
    return list;
  }

  SosDerivation? activeLocalSos({int? nowSeconds}) {
    for (final s in sosAlerts(nowSeconds: nowSeconds)) {
      if (s.sos.isLocal &&
          (s.status == SosStatus.active || s.status == SosStatus.acknowledged)) {
        return s;
      }
    }
    return null;
  }

  List<HazardCluster> hazardClusters({int? nowSeconds}) {
    final now = nowSeconds ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    return clusterHazards(messages, nowSeconds: now);
  }

  List<ResolvedShelter> shelters({
    bool includeUnverified = false,
    bool includeClosed = false,
    int? nowSeconds,
  }) {
    final now = nowSeconds ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    return resolveShelters(
      messages,
      nowSeconds: now,
      includeUnverified: includeUnverified,
      includeClosed: includeClosed,
      userLat: locationFix?.lat,
      userLng: locationFix?.lng,
    );
  }

  double? distanceMetersTo(double? lat, double? lng) {
    final fix = locationFix;
    if (fix == null || lat == null || lng == null) return null;
    return haversineDistanceMeters(fix.lat, fix.lng, lat, lng);
  }

  MeshUiState copyWith({
    MeshBootStatus? bootStatus,
    PlayServicesStatus? playServicesStatus,
    MeshPermissionsState? permissionsState,
    String? deviceId,
    bool? isAdvertising,
    bool? isDiscovering,
    bool? batterySaver,
    GeoFix? locationFix,
    IdentityKeyPair? responderIdentity,
    bool clearResponder = false,
    TrustService? trustService,
    List<NearbyPeerTelemetry>? peers,
    List<StoredMessage>? messages,
    Map<DropReason, int>? dropCounts,
    int? relayedCount,
    List<String>? logs,
    MeshAlertBanner? alertBanner,
    bool clearAlertBanner = false,
    String? errorMessage,
  }) {
    return MeshUiState(
      bootStatus: bootStatus ?? this.bootStatus,
      playServicesStatus: playServicesStatus ?? this.playServicesStatus,
      permissionsState: permissionsState ?? this.permissionsState,
      deviceId: deviceId ?? this.deviceId,
      isAdvertising: isAdvertising ?? this.isAdvertising,
      isDiscovering: isDiscovering ?? this.isDiscovering,
      batterySaver: batterySaver ?? this.batterySaver,
      locationFix: locationFix ?? this.locationFix,
      responderIdentity:
          clearResponder ? null : (responderIdentity ?? this.responderIdentity),
      trustService: trustService ?? this.trustService,
      peers: peers ?? this.peers,
      messages: messages ?? this.messages,
      dropCounts: dropCounts ?? this.dropCounts,
      relayedCount: relayedCount ?? this.relayedCount,
      logs: logs ?? this.logs,
      alertBanner: clearAlertBanner ? null : (alertBanner ?? this.alertBanner),
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class _EmptyTrust implements TrustService {
  const _EmptyTrust();

  @override
  TrustTier evaluateTrust({
    required MessageType type,
    required String originPub,
    required bool signatureValid,
  }) =>
      signatureValid ? TrustTier.signedPeer : TrustTier.unverified;

  @override
  bool isTrustedResponderPub(String originPub) => false;

  @override
  String? responderNameForPub(String originPub) => null;

  @override
  List<TrustedResponder> get responders => const [];
}

class MeshController extends Notifier<MeshUiState> {
  static const int _maxLogLines = 120;
  static const String _onboardingKey = 'onboarding_done';
  static const String _batterySaverKey = 'battery_saver';
  static const Uuid _uuid = Uuid();

  late final PlatformChecks _platformChecks;
  late final PermissionService _permissionService;
  late final DeviceIdentityStore _identityStore;
  late final LocationService _locationService;

  final List<String> _logBuffer = <String>[];
  AppDatabase? _db;
  DriftMessageStore? _driftStore;
  MessageStore? _store;
  ExpiryService? _expiryService;
  NearbyTransport? _transport;
  MeshEngine? _engine;
  Timer? _tickTimer;
  StreamSubscription<StoredMessage>? _acceptedSub;
  StreamSubscription<DropEvent>? _dropSub;
  bool _initialized = false;
  bool _onboardingDone = false;

  @override
  MeshUiState build() {
    _platformChecks = PlatformChecks();
    _permissionService = PermissionService(platformChecks: _platformChecks);
    _identityStore = DeviceIdentityStore();
    _locationService = LocationService();

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

  Future<void> _ensureDatabaseOpen() async {
    if (_db != null && _driftStore != null) return;
    final db = AppDatabase(driftDatabase(name: 'mesh_rescue'));
    final driftStore = DriftMessageStore(db);
    _db = db;
    _driftStore = driftStore;
    _store = driftStore;
    _onboardingDone = (await driftStore.getSetting(_onboardingKey)) == 'true';
    final batteryFlag = (await driftStore.getSetting(_batterySaverKey)) == 'true';
    state = state.copyWith(batterySaver: batteryFlag);
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

    await _ensureDatabaseOpen();
    if (!_onboardingDone) {
      state = state.copyWith(
        bootStatus: MeshBootStatus.onboarding,
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

  Future<void> completeOnboarding() async {
    _onboardingDone = true;
    await _driftStore?.setSetting(_onboardingKey, 'true');
    await recheckAndStart();
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
      await _shutdownMeshOnly();
      await _ensureDatabaseOpen();
      final store = _store!;
      const clock = SystemClock();

      final trustJson =
          await rootBundle.loadString('assets/trusted_responders.json');
      final trustService = TrustService.fromJsonString(trustJson);
      final identity = await _identityStore.loadOrCreate();

      final transport = NearbyTransport(
        deviceId: identity.origin,
        clock: clock,
        logSink: _appendLog,
      )..setBatterySaver(state.batterySaver);

      final engine = MeshEngine(
        transport: transport,
        store: store,
        signer: Ed25519Signer(),
        identity: identity,
        trustService: trustService,
        clock: clock,
        batterySaver: state.batterySaver,
        minSendSpacingMillis: 40,
      );
      final expiry = ExpiryService(store: store, clock: clock);
      await expiry.purgeIfDue(force: true);

      _transport = transport;
      _engine = engine;
      _expiryService = expiry;

      _acceptedSub = engine.onMessageAccepted.listen((msg) {
        _appendLog(
          '[MESH] Accepted ${msg.type.wireName} id=${msg.id.substring(0, 8)} '
          'from=${msg.envelope.origin} hops=${msg.envelope.hops} ttl=${msg.envelope.ttl}',
        );
        if (!msg.isLocal) {
          _maybeRaiseBanner(msg, trustService);
        }
        unawaited(_refreshSnapshot());
      });
      _dropSub = engine.onDrop.listen((drop) {
        _appendLog(
          '[MESH] Drop ${drop.reason.code} peer=${drop.peerId}: ${drop.detail}',
        );
        unawaited(_refreshTelemetryOnly());
      });

      await engine.start();
      _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        unawaited(_onTick());
      });

      final fix = await _locationService.getCurrentOrLastFix();
      state = state.copyWith(
        bootStatus: MeshBootStatus.ready,
        playServicesStatus: gms,
        permissionsState: perms,
        deviceId: identity.origin,
        trustService: trustService,
        locationFix: fix,
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

  void _maybeRaiseBanner(StoredMessage msg, TrustService trustService) {
    if (msg.type == MessageType.sos) {
      final p = msg.envelope.parseSosPayload();
      HapticFeedback.heavyImpact();
      state = state.copyWith(
        alertBanner: MeshAlertBanner(
          title: 'Incoming SOS (${p.category.wireName.toUpperCase()})',
          body: '${p.people} people • from ${msg.envelope.origin}'
              '${p.note.isNotEmpty ? " • ${p.note}" : ""}',
          isSos: true,
          timestampSec: msg.receivedAt,
        ),
      );
    } else if (msg.type == MessageType.shelter &&
        msg.trust == TrustTier.verifiedResponder) {
      final p = msg.envelope.parseShelterPayload();
      final rName =
          trustService.responderNameForPub(msg.envelope.originPub) ?? 'Responder';
      state = state.copyWith(
        alertBanner: MeshAlertBanner(
          title: 'Verified Shelter: ${p.name}',
          body: '${p.status.wireName} • $rName',
          isSos: false,
          timestampSec: msg.receivedAt,
        ),
      );
    }
  }

  void dismissAlertBanner() {
    state = state.copyWith(clearAlertBanner: true);
  }

  Future<void> toggleBatterySaver(bool enabled) async {
    await _driftStore?.setSetting(_batterySaverKey, enabled.toString());
    _engine?.batterySaver = enabled;
    _transport?.setBatterySaver(enabled);
    state = state.copyWith(batterySaver: enabled);
    _appendLog('[MESH] Battery saver ${enabled ? "ENABLED" : "DISABLED"}');
  }

  Future<GeoFix?> refreshLocation() async {
    final fix = await _locationService.getCurrentOrLastFix();
    if (fix != null) {
      state = state.copyWith(locationFix: fix);
    }
    return fix;
  }

  Future<void> sendSos({
    required SosCategory category,
    required int people,
    String note = '',
    String? contact,
  }) async {
    final engine = _engine;
    if (engine == null) return;
    final fix = await refreshLocation();
    await engine.publishSos(
      payload: SosPayload(
        category: category,
        people: people,
        note: note.trim(),
        contact: (contact == null || contact.trim().isEmpty)
            ? null
            : contact.trim(),
      ),
      lat: fix?.lat,
      lng: fix?.lng,
    );
    await _refreshSnapshot();
  }

  Future<void> cancelLocalSos(String sosId) async {
    final engine = _engine;
    if (engine == null) return;
    await engine.publishAck(
      sosId: sosId,
      payload: const AckPayload(
        status: AckStatus.cancelled,
        note: "I'm safe",
      ),
    );
    await _refreshSnapshot();
  }

  Future<bool> reportHazard({
    required HazardKind kind,
    required int severity,
    String note = '',
    String? confirmRefId,
    double? fallbackLat,
    double? fallbackLng,
  }) async {
    final engine = _engine;
    if (engine == null) return false;
    final fix = await refreshLocation();
    final lat = fix?.lat ?? fallbackLat;
    final lng = fix?.lng ?? fallbackLng;
    if (lat == null || lng == null) {
      return false;
    }
    await engine.publishHazard(
      payload: HazardPayload(
        kind: kind,
        severity: severity,
        note: note.trim(),
      ),
      lat: lat,
      lng: lng,
      refId: confirmRefId,
    );
    await _refreshSnapshot();
    return true;
  }

  Future<bool> unlockResponderMode(String pin) async {
    final id = await DemoResponderKey.unlockWithPin(pin.trim());
    if (id == null) return false;
    state = state.copyWith(responderIdentity: id);
    _appendLog('[MESH] Responder mode unlocked (${id.origin})');
    return true;
  }

  void lockResponderMode() {
    state = state.copyWith(clearResponder: true);
    _appendLog('[MESH] Responder mode locked');
  }

  Future<bool> publishVerifiedShelter({
    required String key,
    required String name,
    required ShelterStatus status,
    required int capacity,
    required List<String> services,
    String note = '',
    double? fallbackLat,
    double? fallbackLng,
  }) async {
    final engine = _engine;
    final responder = state.responderIdentity;
    if (engine == null || responder == null) return false;

    final fix = await refreshLocation();
    final lat = fix?.lat ?? fallbackLat;
    final lng = fix?.lng ?? fallbackLng;
    if (lat == null || lng == null) return false;

    final cleanKey = key.trim();
    var maxSeq = 0;
    for (final m in state.messages) {
      if (m.type == MessageType.shelter &&
          m.envelope.origin == responder.origin) {
        final p = m.envelope.parseShelterPayload();
        if (p.key == cleanKey && p.seq > maxSeq) {
          maxSeq = p.seq;
        }
      }
    }

    await engine.publishShelter(
      payload: ShelterPayload(
        key: cleanKey,
        name: name.trim(),
        status: status,
        capacity: capacity,
        services: services,
        note: note.trim(),
        seq: maxSeq + 1,
      ),
      lat: lat,
      lng: lng,
      signingIdentity: responder,
    );
    await _refreshSnapshot();
    return true;
  }

  Future<void> publishResponderAck({
    required String sosId,
    required AckStatus status,
    String note = '',
  }) async {
    final engine = _engine;
    final responder = state.responderIdentity;
    if (engine == null || responder == null) return;
    await engine.publishAck(
      sosId: sosId,
      payload: AckPayload(status: status, note: note.trim()),
      signingIdentity: responder,
    );
    await _refreshSnapshot();
  }

  /// Security demo tool per SECURITY_TRUST.md §7:
  /// 1) Injects an unsigned shelter into the receive pipeline (dropped as BAD_SIG).
  /// 2) Broadcasts a shelter signed by an untrusted random peer key (stored ONLY as UNVERIFIED).
  Future<void> injectForgedShelterDemo() async {
    final engine = _engine;
    if (engine == null) return;
    final fix = state.locationFix;
    final lat = fix?.lat ?? 21.4669;
    final lng = fix?.lng ?? 83.9812;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // 1) Unsigned shelter frame -> BAD_SIG drop.
    final unsignedEnv = Envelope(
      id: _uuid.v4(),
      type: MessageType.shelter,
      origin: engine.identity.origin,
      originPub: engine.identity.publicKeyBase64,
      ts: nowSec,
      lat: lat,
      lng: lng,
      refId: null,
      payload: const ShelterPayload(
        key: 'forged-unsigned-demo',
        name: 'FORGED Unsigned Safe Camp',
        status: ShelterStatus.open,
        capacity: 500,
        services: ['water', 'food'],
        note: 'Attack: unsigned payload',
        seq: 1,
      ).toJson(),
      sig: '',
      ttl: 10,
      hops: 0,
    );
    await engine.receiveFrame(
      'forged-demo',
      FrameCodec.encode(MsgFrame(envelope: unsignedEnv)),
    );

    // 2) Shelter signed by an untrusted random key -> accepted as UNVERIFIED only.
    final untrustedSeed = List<int>.generate(
      32,
      (_) => Random.secure().nextInt(256),
    );
    final untrustedKey = await Ed25519Signer().loadKeyPairFromSeed(untrustedSeed);
    await engine.publishShelter(
      payload: const ShelterPayload(
        key: 'forged-untrusted-demo',
        name: 'Community / Forged Shelter (Untrusted)',
        status: ShelterStatus.open,
        capacity: 300,
        services: ['water'],
        note: 'Signed by untrusted key — must NOT show Verified',
        seq: 1,
      ),
      lat: lat + 0.001,
      lng: lng + 0.001,
      signingIdentity: untrustedKey,
    );
    await _refreshSnapshot();
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
    final fix = state.locationFix;
    final msg = await engine.publishHazard(
      payload: HazardPayload(
        kind: HazardKind.other,
        severity: 1,
        note: '$note from ${engine.identity.origin}',
      ),
      lat: fix?.lat ?? 21.4669,
      lng: fix?.lng ?? 83.9812,
    );
    _appendLog(
      '[MESH] Published test msg id=${msg.id.substring(0, 8)} origin=${msg.envelope.origin}',
    );
    await _refreshSnapshot();
  }

  Future<void> _onTick() async {
    final engine = _engine;
    if (engine == null) return;
    await engine.outbox.flush(engine.connectedPeers);
    await engine.syncManager.tickPeriodicInv(engine.connectedPeers);
    await engine.outbox.tickLocalSosRebroadcast(
      engine.connectedPeers,
      batterySaver: engine.batterySaver,
    );
    final purged = await _expiryService?.purgeIfDue() ?? 0;
    if (purged > 0) {
      await _refreshSnapshot();
    } else {
      await _refreshTelemetryOnly();
    }
  }

  Future<void> _refreshTelemetryOnly() async {
    final transport = _transport;
    final engine = _engine;
    if (transport == null || engine == null) return;
    state = state.copyWith(
      isAdvertising: transport.isAdvertising,
      isDiscovering: transport.isDiscovering,
      peers: transport.peerTelemetry,
      dropCounts: engine.dropCounts,
      relayedCount: engine.relayedCount,
      logs: List<String>.unmodifiable(_logBuffer),
    );
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

  Future<void> _shutdownMeshOnly() async {
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
    _expiryService = null;
  }

  Future<void> _shutdownEngine() async {
    await _shutdownMeshOnly();
    await _db?.close();
    _db = null;
    _driftStore = null;
    _store = null;
  }
}
