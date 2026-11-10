import 'package:mesh_rescue/crypto/signer.dart';
import 'package:mesh_rescue/data/message_store.dart';
import 'package:mesh_rescue/engine/clock.dart';
import 'package:mesh_rescue/engine/models/frame.dart';
import 'package:mesh_rescue/engine/outbox.dart';
import 'package:mesh_rescue/transport/mesh_transport.dart';

/// Anti-entropy HELLO / INV / REQ / MSG sync coordinator.
class SyncManager {
  static const int periodicInvIntervalSeconds = 60;

  final MessageStore store;
  final MeshTransport transport;
  final IdentityKeyPair identity;
  final OutboxScheduler outbox;
  final Clock clock;

  final Set<String> _helloVerifiedPeers = <String>{};
  final Map<String, int> _lastInvSentSec = <String, int>{};

  SyncManager({
    required this.store,
    required this.transport,
    required this.identity,
    required this.outbox,
    required this.clock,
  });

  bool isPeerHandshakeComplete(String peerId) =>
      _helloVerifiedPeers.contains(peerId);

  Future<void> onPeerConnected(String peerId) async {
    final hello = HelloFrame(
      v: HelloFrame.currentVersion,
      deviceId: identity.origin,
      pub: identity.publicKeyBase64,
    );
    await transport.send(peerId, FrameCodec.encode(hello));
  }

  void onPeerDisconnected(String peerId) {
    _helloVerifiedPeers.remove(peerId);
    _lastInvSentSec.remove(peerId);
  }

  Future<void> handleHello(String peerId, HelloFrame frame) async {
    if (frame.v != HelloFrame.currentVersion) {
      await transport.disconnectPeer(peerId);
      onPeerDisconnected(peerId);
      return;
    }
    _helloVerifiedPeers.add(peerId);
    await sendInv(peerId);
  }

  Future<void> sendInv(String peerId) async {
    final nowSec = clock.nowSeconds();
    _lastInvSentSec[peerId] = nowSec;
    final items = await store.getNonExpiredForInv(
      nowSeconds: nowSec,
      limit: InvFrame.maxItemsPerSyncRound,
    );
    if (items.isEmpty) {
      await transport.send(
        peerId,
        FrameCodec.encode(const InvFrame(items: [])),
      );
      return;
    }
    for (var i = 0; i < items.length; i += InvFrame.maxItemsPerFrame) {
      final end = (i + InvFrame.maxItemsPerFrame).clamp(0, items.length);
      final chunk = items
          .sublist(i, end)
          .map((m) => InvItem(id: m.id, type: m.type, ts: m.envelope.ts))
          .toList(growable: false);
      await transport.send(peerId, FrameCodec.encode(InvFrame(items: chunk)));
    }
  }

  Future<void> handleInv(String peerId, InvFrame frame) async {
    if (frame.items.isEmpty) return;

    final nowSec = clock.nowSeconds();
    final peerIds = frame.items.map((e) => e.id).toList(growable: false);
    outbox.markPeerConfirmedHas(peerId, peerIds);
    for (final id in peerIds) {
      if (await store.hasMessage(id)) {
        await store.markSentTo(id, peerId, nowSec);
      }
    }

    final missingIds = <String>[];
    for (final item in frame.items) {
      if (!await store.hasMessage(item.id)) {
        missingIds.add(item.id);
      }
    }
    if (missingIds.isEmpty) return;

    for (var i = 0; i < missingIds.length; i += ReqFrame.maxIdsPerFrame) {
      final end = (i + ReqFrame.maxIdsPerFrame).clamp(0, missingIds.length);
      final chunk = missingIds.sublist(i, end);
      await transport.send(peerId, FrameCodec.encode(ReqFrame(ids: chunk)));
    }
  }

  Future<void> handleReq(String peerId, ReqFrame frame) async {
    final nowSec = clock.nowSeconds();
    for (final id in frame.ids) {
      final msg = await store.getMessage(id);
      if (msg == null) continue;
      if (msg.envelope.ttl <= 0) continue;
      await transport.send(
        peerId,
        FrameCodec.encode(MsgFrame(envelope: msg.envelope)),
      );
      await store.markSentTo(id, peerId, nowSec);
    }
  }

  Future<void> tickPeriodicInv(Iterable<String> connectedPeers) async {
    final nowSec = clock.nowSeconds();
    for (final peerId in connectedPeers) {
      if (!_helloVerifiedPeers.contains(peerId)) continue;
      final last = _lastInvSentSec[peerId];
      if (last == null || nowSec - last >= periodicInvIntervalSeconds) {
        await sendInv(peerId);
      }
    }
  }
}

