import 'dart:typed_data';

final class PeerConnectedEvent {
  final String peerId;
  final String? endpointName;

  const PeerConnectedEvent({
    required this.peerId,
    this.endpointName,
  });
}

final class PeerDisconnectedEvent {
  final String peerId;

  const PeerDisconnectedEvent({required this.peerId});
}

final class IncomingFrameEvent {
  final String peerId;
  final Uint8List bytes;

  const IncomingFrameEvent({
    required this.peerId,
    required this.bytes,
  });
}

/// Transport abstraction implemented by NearbyTransport (Phase 3) and
/// SimTransport (Phase 2).
abstract interface class MeshTransport {
  String get deviceId;

  Stream<PeerConnectedEvent> get onPeerConnected;
  Stream<PeerDisconnectedEvent> get onPeerDisconnected;
  Stream<IncomingFrameEvent> get onFrameReceived;

  Future<void> start();
  Future<void> stop();
  Future<void> send(String peerId, Uint8List bytes);
  Future<void> disconnectPeer(String peerId);
}

