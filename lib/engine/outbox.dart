import 'package:mesh_rescue/data/message_store.dart';
import 'package:mesh_rescue/engine/clock.dart';
import 'package:mesh_rescue/engine/models/enums.dart';
import 'package:mesh_rescue/engine/models/frame.dart';
import 'package:mesh_rescue/transport/mesh_transport.dart';

/// Outbox scheduler:
/// - Priority order: SOS > ACK > SHELTER > HAZARD (newest first within class)
/// - One frame sent per peer per tick with configurable min spacing
/// - Never sends the same message to the same peer twice
/// - Rebroadcasts local un-ACKed SOS every 30s (60s in battery saver) to peers
///   that have not yet confirmed holding that SOS ID in INV.
class OutboxScheduler {
  final MessageStore store;
  final MeshTransport transport;
  final Clock clock;
  final int minSendSpacingMillis;

  final Map<String, int> _lastPeerSendMillis = <String, int>{};
  final Map<String, Set<String>> _peerConfirmedIds = <String, Set<String>>{};
  final Map<String, int> _lastLocalSosBroadcastSec = <String, int>{};

  OutboxScheduler({
    required this.store,
    required this.transport,
    required this.clock,
    this.minSendSpacingMillis = 20,
  });

  void markPeerConfirmedHas(String peerId, Iterable<String> ids) {
    final set = _peerConfirmedIds.putIfAbsent(peerId, () => <String>{});
    set.addAll(ids);
  }

  void clearPeer(String peerId) {
    _lastPeerSendMillis.remove(peerId);
    _peerConfirmedIds.remove(peerId);
  }

  /// Sends at most one highest-priority unsent message per connected peer.
  /// Returns the number of MSG frames dispatched.
  Future<int> flush(Iterable<String> connectedPeers) async {
    final nowSec = clock.nowSeconds();
    final nowMs = clock.nowMillis();
    var sentCount = 0;

    for (final peerId in connectedPeers) {
      final lastMs = _lastPeerSendMillis[peerId];
      if (lastMs != null && nowMs - lastMs < minSendSpacingMillis) {
        continue;
      }

      final unsent = await store.getUnsentForPeer(peerId, nowSeconds: nowSec);
      StoredMessage? candidate;
      for (final msg in unsent) {
        if (msg.envelope.ttl <= 0) continue;
        if (_peerConfirmedIds[peerId]?.contains(msg.id) ?? false) {
          await store.markSentTo(msg.id, peerId, nowSec);
          continue;
        }
        candidate = msg;
        break;
      }
      if (candidate == null) continue;

      final bytes = FrameCodec.encode(MsgFrame(envelope: candidate.envelope));
      await transport.send(peerId, bytes);
      await store.markSentTo(candidate.id, peerId, nowSec);
      _lastPeerSendMillis[peerId] = nowMs;
      if (candidate.isLocal && candidate.type == MessageType.sos) {
        _lastLocalSosBroadcastSec[candidate.id] = nowSec;
      }
      sentCount++;
    }
    return sentCount;
  }

  /// Checks locally originated un-ACKed SOS alerts and dispatches rebroadcasts
  /// on schedule (30s normal, 60s battery saver) to any connected peer that
  /// has not confirmed holding the SOS ID via INV.
  Future<int> tickLocalSosRebroadcast(
    Iterable<String> connectedPeers, {
    required bool batterySaver,
  }) async {
    final peers = connectedPeers.toList(growable: false);
    if (peers.isEmpty) return 0;

    final intervalSec = batterySaver ? 60 : 30;
    final nowSec = clock.nowSeconds();
    final allSos = await store.getMessagesByType(MessageType.sos);
    var rebroadcastCount = 0;

    for (final sos in allSos) {
      if (!sos.isLocal) continue;
      if (nowSec - sos.receivedAt >= ExpiryDurations.sosSeconds) continue;
      if (await _isSosAcknowledgedOrResolved(sos)) continue;

      final lastTick = _lastLocalSosBroadcastSec[sos.id] ?? sos.receivedAt;
      if (nowSec - lastTick < intervalSec) continue;

      _lastLocalSosBroadcastSec[sos.id] = nowSec;
      final bytes = FrameCodec.encode(MsgFrame(envelope: sos.envelope));
      for (final peerId in peers) {
        final confirmed = _peerConfirmedIds[peerId]?.contains(sos.id) ?? false;
        if (confirmed) continue;
        await transport.send(peerId, bytes);
        await store.markSentTo(sos.id, peerId, nowSec);
        rebroadcastCount++;
      }
    }
    return rebroadcastCount;
  }

  Future<bool> _isSosAcknowledgedOrResolved(StoredMessage sos) async {
    final acks = await store.getMessagesByRefId(sos.id);
    for (final ack in acks) {
      if (ack.type == MessageType.ack) {
        return true;
      }
    }
    return false;
  }
}

