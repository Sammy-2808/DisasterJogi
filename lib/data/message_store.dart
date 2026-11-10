import 'package:mesh_rescue/engine/models/envelope.dart';
import 'package:mesh_rescue/engine/models/enums.dart';

class StoredMessage {
  final Envelope envelope;
  final int receivedAt;
  final String? geohash;
  final TrustTier trust;
  final bool isLocal;

  const StoredMessage({
    required this.envelope,
    required this.receivedAt,
    required this.geohash,
    required this.trust,
    required this.isLocal,
  });

  String get id => envelope.id;
  MessageType get type => envelope.type;
}

abstract final class ExpiryDurations {
  static const int sosSeconds = 24 * 3600;
  static const int hazardDefaultSeconds = 12 * 3600;
  static const int hazardConfirmationBonusSeconds = 6 * 3600;
  static const int hazardResponderSeconds = 48 * 3600;
  static const int shelterSeconds = 72 * 3600;
}

/// Abstract persistence contract implemented by InMemoryMessageStore (Phase 2)
/// and DriftMessageStore (Phase 4).
abstract interface class MessageStore {
  static const int defaultMaxMessages = 2000;

  Future<bool> hasMessage(String id);
  Future<StoredMessage?> getMessage(String id);
  Future<List<StoredMessage>> getAllMessages();
  Future<List<StoredMessage>> getMessagesByType(MessageType type);
  Future<List<StoredMessage>> getMessagesByRefId(String refId);

  Future<void> saveMessage(StoredMessage message, {required int nowSeconds});
  Future<int> countMessages();

  /// Returns non-expired messages ordered SOS-first, then newest `receivedAt` first.
  Future<List<StoredMessage>> getNonExpiredForInv({
    required int nowSeconds,
    int limit = 200,
  });

  Future<bool> hasBeenSentTo(String messageId, String peerId);
  Future<void> markSentTo(String messageId, String peerId, int sentAtSeconds);
  Future<List<StoredMessage>> getUnsentForPeer(String peerId, {required int nowSeconds});

  Future<int> purgeExpired(int nowSeconds);
}

/// Pure-Dart in-memory message store for tests and simulator nodes.
final class InMemoryMessageStore implements MessageStore {
  final int maxMessages;
  final Map<String, StoredMessage> _messages = <String, StoredMessage>{};
  final Map<String, Map<String, int>> _outboxSent =
      <String, Map<String, int>>{};

  InMemoryMessageStore({this.maxMessages = MessageStore.defaultMaxMessages});

  @override
  Future<bool> hasMessage(String id) async => _messages.containsKey(id);

  @override
  Future<StoredMessage?> getMessage(String id) async => _messages[id];

  @override
  Future<List<StoredMessage>> getAllMessages() async =>
      List<StoredMessage>.unmodifiable(_messages.values);

  @override
  Future<List<StoredMessage>> getMessagesByType(MessageType type) async =>
      _messages.values.where((m) => m.type == type).toList(growable: false);

  @override
  Future<List<StoredMessage>> getMessagesByRefId(String refId) async =>
      _messages.values
          .where((m) => m.envelope.refId == refId)
          .toList(growable: false);

  @override
  Future<int> countMessages() async => _messages.length;

  @override
  Future<void> saveMessage(
    StoredMessage message, {
    required int nowSeconds,
  }) async {
    _messages[message.id] = message;
    if (_messages.length > maxMessages) {
      await _evictToCap(nowSeconds);
    }
  }

  @override
  Future<List<StoredMessage>> getNonExpiredForInv({
    required int nowSeconds,
    int limit = 200,
  }) async {
    final active = _messages.values
        .where((m) => m.envelope.ttl > 0 && !isMessageExpired(m, nowSeconds))
        .toList(growable: true);

    active.sort((a, b) {
      final aSos = a.type == MessageType.sos ? 0 : 1;
      final bSos = b.type == MessageType.sos ? 0 : 1;
      if (aSos != bSos) return aSos.compareTo(bSos);
      final recvCmp = b.receivedAt.compareTo(a.receivedAt);
      if (recvCmp != 0) return recvCmp;
      return b.envelope.ts.compareTo(a.envelope.ts);
    });

    if (active.length <= limit) return active;
    return active.sublist(0, limit);
  }

  @override
  Future<bool> hasBeenSentTo(String messageId, String peerId) async {
    return _outboxSent[messageId]?.containsKey(peerId) ?? false;
  }

  @override
  Future<void> markSentTo(
    String messageId,
    String peerId,
    int sentAtSeconds,
  ) async {
    final peers = _outboxSent.putIfAbsent(messageId, () => <String, int>{});
    peers[peerId] = sentAtSeconds;
  }

  @override
  Future<List<StoredMessage>> getUnsentForPeer(
    String peerId, {
    required int nowSeconds,
  }) async {
    final unsent = <StoredMessage>[];
    for (final msg in _messages.values) {
      if (isMessageExpired(msg, nowSeconds)) continue;
      if (_outboxSent[msg.id]?.containsKey(peerId) ?? false) continue;
      unsent.add(msg);
    }
    unsent.sort(_compareOutboxPriority);
    return unsent;
  }

  @override
  Future<int> purgeExpired(int nowSeconds) async {
    final toRemove = <String>[];
    for (final msg in _messages.values) {
      if (isMessageExpired(msg, nowSeconds)) {
        toRemove.add(msg.id);
      }
    }
    for (final id in toRemove) {
      _messages.remove(id);
      _outboxSent.remove(id);
    }
    return toRemove.length;
  }

  bool isMessageExpired(StoredMessage msg, int nowSeconds) {
    switch (msg.type) {
      case MessageType.sos:
        // If a terminal ACK (RESOLVED/CANCELLED) exists, consider expired/closed for sync?
        // Wait: keep SOS + its terminal ACK for the 24h window unless past 24h, so late joiners
        // learn it was resolved rather than keeping stale ACTIVE state.
        return nowSeconds - msg.receivedAt >= ExpiryDurations.sosSeconds;
      case MessageType.hazard:
        final lifetime = _hazardLifetimeSeconds(msg);
        return nowSeconds - msg.receivedAt >= lifetime;
      case MessageType.shelter:
        return nowSeconds - msg.receivedAt >= ExpiryDurations.shelterSeconds;
      case MessageType.ack:
        final refId = msg.envelope.refId;
        if (refId == null) {
          return nowSeconds - msg.receivedAt >= ExpiryDurations.sosSeconds;
        }
        final sos = _messages[refId];
        if (sos == null) {
          return nowSeconds - msg.receivedAt >= ExpiryDurations.sosSeconds;
        }
        return isMessageExpired(sos, nowSeconds);
    }
  }

  int _hazardLifetimeSeconds(StoredMessage hazard) {
    if (hazard.trust == TrustTier.verifiedResponder) {
      return ExpiryDurations.hazardResponderSeconds;
    }
    final confirmations = _messages.values.where(
      (m) =>
          m.type == MessageType.hazard &&
          m.envelope.refId == hazard.id &&
          m.envelope.origin != hazard.envelope.origin,
    );
    final distinctOrigins = confirmations.map((m) => m.envelope.origin).toSet();
    return ExpiryDurations.hazardDefaultSeconds +
        distinctOrigins.length * ExpiryDurations.hazardConfirmationBonusSeconds;
  }

  Future<void> _evictToCap(int nowSeconds) async {
    await purgeExpired(nowSeconds);
    if (_messages.length <= maxMessages) return;

    final candidates = _messages.values.toList(growable: true);
    candidates.sort((a, b) {
      final tierCmp = _evictionBucket(a).compareTo(_evictionBucket(b));
      if (tierCmp != 0) return tierCmp;
      return a.receivedAt.compareTo(b.receivedAt);
    });

    final removeCount = _messages.length - maxMessages;
    for (var i = 0; i < removeCount; i++) {
      final victim = candidates[i];
      _messages.remove(victim.id);
      _outboxSent.remove(victim.id);
    }
  }

  /// Lower number = evicted earlier.
  /// 0: unverified messages (e.g. forged shelters)
  /// 1: peer hazards
  /// 2: peer ACKs / responder hazards
  /// 3: SOS & verified shelters (evicted last)
  int _evictionBucket(StoredMessage msg) {
    if (msg.trust == TrustTier.unverified) return 0;
    if (msg.type == MessageType.hazard &&
        msg.trust != TrustTier.verifiedResponder) {
      return 1;
    }
    if (msg.type == MessageType.sos ||
        (msg.type == MessageType.shelter &&
            msg.trust == TrustTier.verifiedResponder)) {
      return 3;
    }
    return 2;
  }

  static int _compareOutboxPriority(StoredMessage a, StoredMessage b) {
    final p = a.type.priorityRank.compareTo(b.type.priorityRank);
    if (p != 0) return p;
    final r = b.receivedAt.compareTo(a.receivedAt);
    if (r != 0) return r;
    return b.envelope.ts.compareTo(a.envelope.ts);
  }
}
