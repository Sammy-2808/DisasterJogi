import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:mesh_rescue/engine/clock.dart';
import 'package:mesh_rescue/engine/models/frame.dart';
import 'package:mesh_rescue/transport/mesh_transport.dart';
import 'package:nearby_connections/nearby_connections.dart';

/// Thin wrapper over the `nearby_connections` plugin so [NearbyTransport] can
/// be unit tested deterministically without physical radios.
abstract interface class NearbyApi {
  Future<bool> startAdvertising(
    String userNickName,
    Strategy strategy, {
    required OnConnectionInitiated onConnectionInitiated,
    required OnConnectionResult onConnectionResult,
    required OnDisconnected onDisconnected,
    required String serviceId,
  });

  Future<void> stopAdvertising();

  Future<bool> startDiscovery(
    String userNickName,
    Strategy strategy, {
    required OnEndpointFound onEndpointFound,
    required OnEndpointLost onEndpointLost,
    required String serviceId,
  });

  Future<void> stopDiscovery();

  Future<bool> requestConnection(
    String userNickName,
    String endpointId, {
    required OnConnectionInitiated onConnectionInitiated,
    required OnConnectionResult onConnectionResult,
    required OnDisconnected onDisconnected,
  });

  Future<bool> acceptConnection(
    String endpointId, {
    required OnPayloadReceived onPayloadReceived,
    OnPayloadTransferUpdate? onPayloadTransferUpdate,
  });

  Future<bool> rejectConnection(String endpointId);
  Future<void> disconnectFromEndpoint(String endpointId);
  Future<void> stopAllEndpoints();
  Future<void> sendBytesPayload(String endpointId, Uint8List bytes);
}

final class FlutterNearbyApi implements NearbyApi {
  final Nearby _nearby;

  FlutterNearbyApi([Nearby? nearby]) : _nearby = nearby ?? Nearby();

  @override
  Future<bool> startAdvertising(
    String userNickName,
    Strategy strategy, {
    required OnConnectionInitiated onConnectionInitiated,
    required OnConnectionResult onConnectionResult,
    required OnDisconnected onDisconnected,
    required String serviceId,
  }) {
    return _nearby.startAdvertising(
      userNickName,
      strategy,
      onConnectionInitiated: onConnectionInitiated,
      onConnectionResult: onConnectionResult,
      onDisconnected: onDisconnected,
      serviceId: serviceId,
    );
  }

  @override
  Future<void> stopAdvertising() => _nearby.stopAdvertising();

  @override
  Future<bool> startDiscovery(
    String userNickName,
    Strategy strategy, {
    required OnEndpointFound onEndpointFound,
    required OnEndpointLost onEndpointLost,
    required String serviceId,
  }) {
    return _nearby.startDiscovery(
      userNickName,
      strategy,
      onEndpointFound: onEndpointFound,
      onEndpointLost: onEndpointLost,
      serviceId: serviceId,
    );
  }

  @override
  Future<void> stopDiscovery() => _nearby.stopDiscovery();

  @override
  Future<bool> requestConnection(
    String userNickName,
    String endpointId, {
    required OnConnectionInitiated onConnectionInitiated,
    required OnConnectionResult onConnectionResult,
    required OnDisconnected onDisconnected,
  }) {
    return _nearby.requestConnection(
      userNickName,
      endpointId,
      onConnectionInitiated: onConnectionInitiated,
      onConnectionResult: onConnectionResult,
      onDisconnected: onDisconnected,
    );
  }

  @override
  Future<bool> acceptConnection(
    String endpointId, {
    required OnPayloadReceived onPayloadReceived,
    OnPayloadTransferUpdate? onPayloadTransferUpdate,
  }) {
    // Note: nearby_connections 4.3.0 parameter name is `onPayLoadRecieved`.
    return _nearby.acceptConnection(
      endpointId,
      onPayLoadRecieved: onPayloadReceived,
      onPayloadTransferUpdate: onPayloadTransferUpdate,
    );
  }

  @override
  Future<bool> rejectConnection(String endpointId) =>
      _nearby.rejectConnection(endpointId);

  @override
  Future<void> disconnectFromEndpoint(String endpointId) =>
      _nearby.disconnectFromEndpoint(endpointId);

  @override
  Future<void> stopAllEndpoints() => _nearby.stopAllEndpoints();

  @override
  Future<void> sendBytesPayload(String endpointId, Uint8List bytes) =>
      _nearby.sendBytesPayload(endpointId, bytes);
}

class NearbyPeerTelemetry {
  final String peerId;
  final String endpointId;
  final String state;
  final int connectedAtSec;
  final int? lastFrameAtSec;

  const NearbyPeerTelemetry({
    required this.peerId,
    required this.endpointId,
    required this.state,
    required this.connectedAtSec,
    this.lastFrameAtSec,
  });
}

/// Google Nearby Connections (`Strategy.P2P_CLUSTER`) implementation of
/// [MeshTransport] per docs/ARCHITECTURE.md section 5 and `.agent/skills/flutter-nearby-mesh`.
class NearbyTransport implements MeshTransport {
  static const String serviceId = 'com.meshrescue.mesh.v1';
  static const int defaultMaxPeers = 4;
  static const int _initialBackoffSeconds = 2;
  static const int _maxBackoffSeconds = 60;

  @override
  final String deviceId;

  final NearbyApi _api;
  final Clock _clock;
  final int maxPeers;
  final void Function(String line)? logSink;

  final StreamController<PeerConnectedEvent> _connectedController =
      StreamController<PeerConnectedEvent>.broadcast();
  final StreamController<PeerDisconnectedEvent> _disconnectedController =
      StreamController<PeerDisconnectedEvent>.broadcast();
  final StreamController<IncomingFrameEvent> _frameController =
      StreamController<IncomingFrameEvent>.broadcast();

  // Maps between Nearby's ephemeral endpointId and stable remote deviceId.
  final Map<String, String> _endpointToPeer = <String, String>{};
  final Map<String, String> _peerToEndpoint = <String, String>{};
  final Map<String, String> _pendingNames = <String, String>{};
  final Set<String> _connectingEndpoints = <String>{};
  final Map<String, int> _connectedAtSec = <String, int>{};
  final Map<String, int> _lastFrameAtSec = <String, int>{};

  // Exponential backoff state keyed by stable peerId (or endpointId fallback).
  final Map<String, int> _backoffSeconds = <String, int>{};
  final Map<String, int> _retryAfterSec = <String, int>{};
  final Map<String, String> _discoveredEndpoints = <String, String>{};

  Timer? _dutyCycleTimer;
  bool _running = false;
  bool _isAdvertising = false;
  bool _isDiscovering = false;
  bool _batterySaver = false;
  bool _dutyCycleDiscoveryOn = true;
  int _dutyPhaseStartSec = 0;

  NearbyTransport({
    required this.deviceId,
    NearbyApi? api,
    Clock? clock,
    this.maxPeers = defaultMaxPeers,
    this.logSink,
  })  : _api = api ?? FlutterNearbyApi(),
        _clock = clock ?? const SystemClock();

  @override
  Stream<PeerConnectedEvent> get onPeerConnected => _connectedController.stream;

  @override
  Stream<PeerDisconnectedEvent> get onPeerDisconnected =>
      _disconnectedController.stream;

  @override
  Stream<IncomingFrameEvent> get onFrameReceived => _frameController.stream;

  bool get isRunning => _running;
  bool get isAdvertising => _isAdvertising;
  bool get isDiscovering => _isDiscovering;
  bool get batterySaver => _batterySaver;

  List<NearbyPeerTelemetry> get peerTelemetry {
    final list = <NearbyPeerTelemetry>[];
    for (final entry in _peerToEndpoint.entries) {
      final peerId = entry.key;
      final endpointId = entry.value;
      list.add(
        NearbyPeerTelemetry(
          peerId: peerId,
          endpointId: endpointId,
          state: 'CONNECTED',
          connectedAtSec: _connectedAtSec[peerId] ?? 0,
          lastFrameAtSec: _lastFrameAtSec[peerId],
        ),
      );
    }
    for (final endpointId in _connectingEndpoints) {
      final peerId = _pendingNames[endpointId] ?? endpointId;
      if (_peerToEndpoint.containsKey(peerId)) continue;
      list.add(
        NearbyPeerTelemetry(
          peerId: peerId,
          endpointId: endpointId,
          state: 'CONNECTING',
          connectedAtSec: 0,
        ),
      );
    }
    return List<NearbyPeerTelemetry>.unmodifiable(list);
  }

  void setBatterySaver(bool enabled) {
    _batterySaver = enabled;
    if (_running) {
      unawaited(_reconcileDiscoveryDutyCycle());
    }
  }

  @override
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _dutyPhaseStartSec = _clock.nowSeconds();
    _dutyCycleDiscoveryOn = true;
    _log('Starting NearbyTransport deviceId=$deviceId serviceId=$serviceId');

    await _startAdvertisingSafe();
    await _startDiscoverySafe();

    _dutyCycleTimer?.cancel();
    _dutyCycleTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_running) return;
      unawaited(_reconcileDiscoveryDutyCycle());
      unawaited(_retryPendingDiscoveries());
    });
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _dutyCycleTimer?.cancel();
    _dutyCycleTimer = null;
    _log('Stopping NearbyTransport');

    try {
      await _api.stopAdvertising();
    } catch (e) {
      _log('stopAdvertising error: $e');
    }
    try {
      await _api.stopDiscovery();
    } catch (e) {
      _log('stopDiscovery error: $e');
    }
    try {
      await _api.stopAllEndpoints();
    } catch (e) {
      _log('stopAllEndpoints error: $e');
    }

    _isAdvertising = false;
    _isDiscovering = false;
    final peers = _peerToEndpoint.keys.toList(growable: false);
    _endpointToPeer.clear();
    _peerToEndpoint.clear();
    _pendingNames.clear();
    _connectingEndpoints.clear();
    _discoveredEndpoints.clear();
    _connectedAtSec.clear();

    for (final peerId in peers) {
      _disconnectedController.add(PeerDisconnectedEvent(peerId: peerId));
    }
  }

  @override
  Future<void> send(String peerId, Uint8List bytes) async {
    if (!_running) return;
    if (bytes.length > FrameCodec.maxFrameBytes) {
      _log('Drop outbound oversized frame (${bytes.length}B) to $peerId');
      return;
    }
    final endpointId = _peerToEndpoint[peerId];
    if (endpointId == null) {
      _log('Cannot send to disconnected peer=$peerId');
      return;
    }
    try {
      await _api.sendBytesPayload(endpointId, bytes);
      _lastFrameAtSec[peerId] = _clock.nowSeconds();
    } catch (e) {
      _log('sendBytesPayload error peer=$peerId endpoint=$endpointId: $e');
    }
  }

  @override
  Future<void> disconnectPeer(String peerId) async {
    final endpointId = _peerToEndpoint[peerId];
    if (endpointId == null) return;
    try {
      await _api.disconnectFromEndpoint(endpointId);
    } catch (e) {
      _log('disconnectFromEndpoint error peer=$peerId: $e');
    }
    _markEndpointDisconnected(endpointId);
  }

  Future<void> _startAdvertisingSafe() async {
    try {
      _isAdvertising = await _api.startAdvertising(
        deviceId,
        Strategy.P2P_CLUSTER,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: serviceId,
      );
      _log('startAdvertising -> $_isAdvertising');
    } catch (e) {
      _isAdvertising = false;
      _log('startAdvertising failed: $e');
    }
  }

  Future<void> _startDiscoverySafe() async {
    if (_isDiscovering) return;
    try {
      _isDiscovering = await _api.startDiscovery(
        deviceId,
        Strategy.P2P_CLUSTER,
        onEndpointFound: _onEndpointFound,
        onEndpointLost: _onEndpointLost,
        serviceId: serviceId,
      );
      _log('startDiscovery -> $_isDiscovering');
    } catch (e) {
      _isDiscovering = false;
      _log('startDiscovery failed: $e');
    }
  }

  Future<void> _stopDiscoverySafe() async {
    if (!_isDiscovering) return;
    try {
      await _api.stopDiscovery();
      _isDiscovering = false;
      _log('stopDiscovery (duty cycle pause)');
    } catch (e) {
      _log('stopDiscovery failed: $e');
    }
  }

  void _onEndpointFound(
    String endpointId,
    String endpointName,
    String foundServiceId,
  ) {
    if (!_running) return;
    if (foundServiceId != serviceId) return;

    final remoteId = endpointName.isNotEmpty ? endpointName : endpointId;
    _discoveredEndpoints[endpointId] = remoteId;
    _pendingNames[endpointId] = remoteId;
    _log('EndpointFound endpoint=$endpointId peer=$remoteId');
    unawaited(_maybeRequestConnection(endpointId, remoteId));
  }

  void _onEndpointLost(String? endpointId) {
    if (endpointId == null) return;
    _discoveredEndpoints.remove(endpointId);
    _log('EndpointLost endpoint=$endpointId');
  }

  Future<void> _maybeRequestConnection(String endpointId, String remoteId) async {
    if (!_running) return;
    if (remoteId == deviceId) return;
    if (_peerToEndpoint.containsKey(remoteId) ||
        _endpointToPeer.containsKey(endpointId) ||
        _connectingEndpoints.contains(endpointId)) {
      return;
    }

    // Degree cap: connected + connecting capped at maxPeers (default 4).
    if (_peerToEndpoint.length + _connectingEndpoints.length >= maxPeers) {
      _log('Degree cap ($maxPeers) reached; ignoring discovery $remoteId');
      return;
    }

    // Deterministic tie-break: only lexicographically smaller deviceId initiates.
    if (deviceId.compareTo(remoteId) >= 0) {
      _log('Tie-break wait: $deviceId >= $remoteId (remote initiates)');
      return;
    }

    final now = _clock.nowSeconds();
    final retryAfter = _retryAfterSec[remoteId] ?? 0;
    if (now < retryAfter) {
      _log('Backoff active for $remoteId (${retryAfter - now}s left)');
      return;
    }

    _connectingEndpoints.add(endpointId);
    _log('Requesting connection to $remoteId ($endpointId)');
    try {
      await _api.requestConnection(
        deviceId,
        endpointId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
    } catch (e) {
      _connectingEndpoints.remove(endpointId);
      _scheduleBackoff(remoteId);
      _log('requestConnection error for $remoteId: $e');
    }
  }

  void _onConnectionInitiated(String endpointId, ConnectionInfo info) {
    if (!_running) return;
    final remoteId =
        info.endpointName.isNotEmpty ? info.endpointName : (_pendingNames[endpointId] ?? endpointId);
    _pendingNames[endpointId] = remoteId;
    _log(
      'ConnectionInitiated endpoint=$endpointId peer=$remoteId incoming=${info.isIncomingConnection}',
    );

    if (_peerToEndpoint.containsKey(remoteId)) {
      _log('Already connected to $remoteId; rejecting duplicate endpoint=$endpointId');
      unawaited(_rejectSafe(endpointId));
      return;
    }
    if (_peerToEndpoint.length >= maxPeers) {
      _log('Degree cap ($maxPeers) reached; rejecting $remoteId');
      unawaited(_rejectSafe(endpointId));
      return;
    }

    _connectingEndpoints.add(endpointId);
    unawaited(_acceptSafe(endpointId, remoteId));
  }

  Future<void> _acceptSafe(String endpointId, String remoteId) async {
    try {
      await _api.acceptConnection(
        endpointId,
        onPayloadReceived: _onPayloadReceived,
        onPayloadTransferUpdate: (endid, update) {
          if (update.status == PayloadStatus.FAILURE) {
            _log('Payload transfer failure endpoint=$endid id=${update.id}');
          }
        },
      );
      _log('Auto-accepted connection endpoint=$endpointId peer=$remoteId');
    } catch (e) {
      _connectingEndpoints.remove(endpointId);
      _scheduleBackoff(remoteId);
      _log('acceptConnection failed endpoint=$endpointId: $e');
    }
  }

  Future<void> _rejectSafe(String endpointId) async {
    try {
      await _api.rejectConnection(endpointId);
    } catch (e) {
      _log('rejectConnection error endpoint=$endpointId: $e');
    }
  }

  void _onConnectionResult(String endpointId, Status status) {
    _connectingEndpoints.remove(endpointId);
    final remoteId = _pendingNames[endpointId] ?? endpointId;

    if (status == Status.CONNECTED) {
      _endpointToPeer[endpointId] = remoteId;
      _peerToEndpoint[remoteId] = endpointId;
      _connectedAtSec[remoteId] = _clock.nowSeconds();
      _backoffSeconds.remove(remoteId);
      _retryAfterSec.remove(remoteId);
      _log('CONNECTED endpoint=$endpointId peer=$remoteId (peers=${_peerToEndpoint.length})');
      _connectedController.add(
        PeerConnectedEvent(peerId: remoteId, endpointName: remoteId),
      );
      unawaited(_reconcileDiscoveryDutyCycle());
    } else {
      _scheduleBackoff(remoteId);
      _log('Connection failed endpoint=$endpointId peer=$remoteId status=$status');
    }
  }

  void _onDisconnected(String endpointId) {
    _markEndpointDisconnected(endpointId);
    unawaited(_reconcileDiscoveryDutyCycle());
  }

  void _markEndpointDisconnected(String endpointId) {
    _connectingEndpoints.remove(endpointId);
    final peerId = _endpointToPeer.remove(endpointId) ?? _pendingNames[endpointId];
    if (peerId != null && _peerToEndpoint[peerId] == endpointId) {
      _peerToEndpoint.remove(peerId);
      _connectedAtSec.remove(peerId);
      _scheduleBackoff(peerId);
      _log('DISCONNECTED endpoint=$endpointId peer=$peerId');
      _disconnectedController.add(PeerDisconnectedEvent(peerId: peerId));
    }
  }

  void _onPayloadReceived(String endpointId, Payload payload) {
    if (payload.type != PayloadType.BYTES) return;
    final bytes = payload.bytes;
    if (bytes == null || bytes.isEmpty) return;

    final peerId = _endpointToPeer[endpointId] ?? _pendingNames[endpointId] ?? endpointId;
    if (bytes.length > FrameCodec.maxFrameBytes) {
      _log('Dropped oversized incoming bytes (${bytes.length}B) from $peerId');
      return;
    }
    _lastFrameAtSec[peerId] = _clock.nowSeconds();
    _frameController.add(
      IncomingFrameEvent(peerId: peerId, bytes: Uint8List.fromList(bytes)),
    );
  }

  void _scheduleBackoff(String peerId) {
    final prev = _backoffSeconds[peerId] ?? 0;
    final next = prev == 0
        ? _initialBackoffSeconds
        : math.min(_maxBackoffSeconds, prev * 2);
    _backoffSeconds[peerId] = next;
    _retryAfterSec[peerId] = _clock.nowSeconds() + next;
  }

  Future<void> _retryPendingDiscoveries() async {
    if (!_running) return;
    if (_peerToEndpoint.length + _connectingEndpoints.length >= maxPeers) return;
    for (final entry in _discoveredEndpoints.entries.toList()) {
      await _maybeRequestConnection(entry.key, entry.value);
    }
  }

  Future<void> _reconcileDiscoveryDutyCycle() async {
    if (!_running) return;
    final peerCount = _peerToEndpoint.length;
    final now = _clock.nowSeconds();

    // Seeking mode (0-1 peers): continuous discovery unless battery saver is on.
    if (peerCount < 2 && !_batterySaver) {
      if (!_isDiscovering) {
        _dutyCycleDiscoveryOn = true;
        _dutyPhaseStartSec = now;
        await _startDiscoverySafe();
      }
      return;
    }

    // Connected mode (2+ peers) or battery saver: cycle discovery 20s ON / 40s OFF
    // (15s ON / 75s OFF in battery saver). Advertising stays ON.
    final onSeconds = _batterySaver ? 15 : 20;
    final offSeconds = _batterySaver ? 75 : 40;
    final elapsed = now - _dutyPhaseStartSec;

    if (_dutyCycleDiscoveryOn && elapsed >= onSeconds) {
      _dutyCycleDiscoveryOn = false;
      _dutyPhaseStartSec = now;
      await _stopDiscoverySafe();
    } else if (!_dutyCycleDiscoveryOn && elapsed >= offSeconds) {
      _dutyCycleDiscoveryOn = true;
      _dutyPhaseStartSec = now;
      await _startDiscoverySafe();
    }
  }

  void _log(String msg) {
    final line = '[MESH] $msg';
    debugPrint(line);
    logSink?.call(line);
  }

  Future<void> dispose() async {
    await stop();
    await _connectedController.close();
    await _disconnectedController.close();
    await _frameController.close();
  }
}
