import 'dart:async';
import 'dart:typed_data';

import 'package:mesh_rescue/transport/mesh_transport.dart';

typedef SimSendCallback = Future<void> Function(
  String fromPeerId,
  String toPeerId,
  Uint8List bytes,
);

typedef SimDisconnectCallback = Future<void> Function(
  String fromPeerId,
  String toPeerId,
);

/// In-memory virtual radio transport driven by [SimWorld].
class SimTransport implements MeshTransport {
  @override
  final String deviceId;

  final SimSendCallback onSend;
  final SimDisconnectCallback onDisconnectRequested;

  final StreamController<PeerConnectedEvent> _connectedController =
      StreamController<PeerConnectedEvent>.broadcast();
  final StreamController<PeerDisconnectedEvent> _disconnectedController =
      StreamController<PeerDisconnectedEvent>.broadcast();
  final StreamController<IncomingFrameEvent> _frameController =
      StreamController<IncomingFrameEvent>.broadcast();

  final Set<String> _connectedPeers = <String>{};
  bool _started = false;

  SimTransport({
    required this.deviceId,
    required this.onSend,
    required this.onDisconnectRequested,
  });

  bool get isStarted => _started;
  Set<String> get connectedPeers => Set<String>.unmodifiable(_connectedPeers);

  @override
  Stream<PeerConnectedEvent> get onPeerConnected => _connectedController.stream;

  @override
  Stream<PeerDisconnectedEvent> get onPeerDisconnected =>
      _disconnectedController.stream;

  @override
  Stream<IncomingFrameEvent> get onFrameReceived => _frameController.stream;

  @override
  Future<void> start() async {
    _started = true;
  }

  @override
  Future<void> stop() async {
    _started = false;
    final peers = _connectedPeers.toList(growable: false);
    for (final p in peers) {
      simulatePeerDisconnected(p);
    }
  }

  @override
  Future<void> send(String peerId, Uint8List bytes) async {
    if (!_started || !_connectedPeers.contains(peerId)) return;
    await onSend(deviceId, peerId, Uint8List.fromList(bytes));
  }

  @override
  Future<void> disconnectPeer(String peerId) async {
    await onDisconnectRequested(deviceId, peerId);
  }

  void simulatePeerConnected(String peerId, {String? endpointName}) {
    if (!_started) return;
    if (_connectedPeers.add(peerId)) {
      _connectedController.add(
        PeerConnectedEvent(peerId: peerId, endpointName: endpointName),
      );
    }
  }

  void simulatePeerDisconnected(String peerId) {
    if (_connectedPeers.remove(peerId)) {
      _disconnectedController.add(PeerDisconnectedEvent(peerId: peerId));
    }
  }

  void deliverIncomingFrame(String fromPeerId, Uint8List bytes) {
    if (!_started || !_connectedPeers.contains(fromPeerId)) return;
    _frameController.add(
      IncomingFrameEvent(peerId: fromPeerId, bytes: bytes),
    );
  }

  Future<void> dispose() async {
    await stop();
    await _connectedController.close();
    await _disconnectedController.close();
    await _frameController.close();
  }
}
