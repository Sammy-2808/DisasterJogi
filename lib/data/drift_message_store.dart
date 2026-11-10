import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:mesh_rescue/data/db.dart';
import 'package:mesh_rescue/data/message_store.dart';
import 'package:mesh_rescue/engine/canonical_json.dart';
import 'package:mesh_rescue/engine/models/envelope.dart';
import 'package:mesh_rescue/engine/models/enums.dart';

/// SQLite-backed [MessageStore] using Drift and the schema in docs/ARCHITECTURE.md §7.
final class DriftMessageStore implements MessageStore {
  final AppDatabase db;
  final int maxMessages;

  DriftMessageStore(
    this.db, {
    this.maxMessages = MessageStore.defaultMaxMessages,
  });

  @override
  Future<bool> hasMessage(String id) async {
    final row = await (db.select(db.messages)
          ..where((m) => m.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  @override
  Future<StoredMessage?> getMessage(String id) async {
    final row = await (db.select(db.messages)
          ..where((m) => m.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  @override
  Future<List<StoredMessage>> getAllMessages() async {
    final rows = await db.select(db.messages).get();
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<List<StoredMessage>> getMessagesByType(MessageType type) async {
    final rows = await (db.select(db.messages)
          ..where((m) => m.type.equals(type.wireName)))
        .get();
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<List<StoredMessage>> getMessagesByRefId(String refId) async {
    final rows = await (db.select(db.messages)
          ..where((m) => m.refId.equals(refId)))
        .get();
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<int> countMessages() async {
    final countExp = db.messages.id.count();
    final query = db.selectOnly(db.messages)..addColumns([countExp]);
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  @override
  Future<void> saveMessage(
    StoredMessage message, {
    required int nowSeconds,
  }) async {
    final env = message.envelope;
    await db.into(db.messages).insertOnConflictUpdate(
          MessagesCompanion(
            id: Value(env.id),
            type: Value(env.type.wireName),
            origin: Value(env.origin),
            originPub: Value(env.originPub),
            ts: Value(env.ts),
            receivedAt: Value(message.receivedAt),
            lat: Value(env.lat),
            lng: Value(env.lng),
            geohash: Value(message.geohash),
            ttl: Value(env.ttl),
            hops: Value(env.hops),
            refId: Value(env.refId),
            payload: Value(canonicalJson(env.payload)),
            sig: Value(env.sig),
            trust: Value(message.trust.wireName),
            isLocal: Value(message.isLocal ? 1 : 0),
          ),
        );
    final total = await countMessages();
    if (total > maxMessages) {
      await _evictToCap(nowSeconds);
    }
  }

  @override
  Future<List<StoredMessage>> getNonExpiredForInv({
    required int nowSeconds,
    int limit = 200,
  }) async {
    final all = await getAllMessages();
    final byId = {for (final m in all) m.id: m};
    final active = all
        .where(
          (m) =>
              m.envelope.ttl > 0 &&
              !MessageStoreRules.isExpired(
                m,
                nowSeconds,
                lookupById: (id) => byId[id],
                lookupByRefId: (refId) =>
                    all.where((x) => x.envelope.refId == refId),
              ),
        )
        .toList(growable: true);

    active.sort(MessageStoreRules.compareInvOrder);
    if (active.length <= limit) return active;
    return active.sublist(0, limit);
  }

  @override
  Future<bool> hasBeenSentTo(String messageId, String peerId) async {
    final row = await (db.select(db.outboxEntries)
          ..where(
            (o) => o.messageId.equals(messageId) & o.peerId.equals(peerId),
          )
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  @override
  Future<void> markSentTo(
    String messageId,
    String peerId,
    int sentAtSeconds,
  ) async {
    await db.into(db.outboxEntries).insertOnConflictUpdate(
          OutboxEntriesCompanion(
            messageId: Value(messageId),
            peerId: Value(peerId),
            sentAt: Value(sentAtSeconds),
          ),
        );
  }

  @override
  Future<List<StoredMessage>> getUnsentForPeer(
    String peerId, {
    required int nowSeconds,
  }) async {
    final all = await getAllMessages();
    final byId = {for (final m in all) m.id: m};
    final sentRows = await (db.select(db.outboxEntries)
          ..where((o) => o.peerId.equals(peerId)))
        .get();
    final sentIds = sentRows.map((r) => r.messageId).toSet();

    final unsent = <StoredMessage>[];
    for (final msg in all) {
      if (sentIds.contains(msg.id)) continue;
      final expired = MessageStoreRules.isExpired(
        msg,
        nowSeconds,
        lookupById: (id) => byId[id],
        lookupByRefId: (refId) => all.where((x) => x.envelope.refId == refId),
      );
      if (expired) continue;
      unsent.add(msg);
    }
    unsent.sort(MessageStoreRules.compareOutboxPriority);
    return unsent;
  }

  @override
  Future<int> purgeExpired(int nowSeconds) async {
    final all = await getAllMessages();
    final byId = {for (final m in all) m.id: m};
    final toRemove = <String>[];
    for (final msg in all) {
      final expired = MessageStoreRules.isExpired(
        msg,
        nowSeconds,
        lookupById: (id) => byId[id],
        lookupByRefId: (refId) => all.where((x) => x.envelope.refId == refId),
      );
      if (expired) {
        toRemove.add(msg.id);
      }
    }
    if (toRemove.isEmpty) return 0;
    await _deleteIds(toRemove);
    return toRemove.length;
  }

  Future<void> _evictToCap(int nowSeconds) async {
    await purgeExpired(nowSeconds);
    final remaining = await getAllMessages();
    if (remaining.length <= maxMessages) return;

    final sorted = List<StoredMessage>.from(remaining)
      ..sort(MessageStoreRules.compareEvictionOrder);
    final removeCount = remaining.length - maxMessages;
    final victimIds = sorted.take(removeCount).map((m) => m.id).toList();
    await _deleteIds(victimIds);
  }

  Future<void> _deleteIds(List<String> ids) async {
    if (ids.isEmpty) return;
    await db.transaction(() async {
      await (db.delete(db.outboxEntries)
            ..where((o) => o.messageId.isIn(ids)))
          .go();
      await (db.delete(db.messages)..where((m) => m.id.isIn(ids))).go();
    });
  }

  Future<String?> getSetting(String key) async {
    final row = await (db.select(db.appSettings)
          ..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> setSetting(String key, String value) async {
    await db.into(db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion(key: Value(key), value: Value(value)),
        );
  }

  StoredMessage _fromRow(MessageRow row) {
    final decodedPayload = Map<String, Object?>.from(
      jsonDecode(row.payload) as Map<String, dynamic>,
    );
    final type = MessageType.fromWire(row.type)!;
    final trust = TrustTier.fromWire(row.trust) ?? TrustTier.unverified;
    return StoredMessage(
      envelope: Envelope(
        id: row.id,
        type: type,
        origin: row.origin,
        originPub: row.originPub,
        ts: row.ts,
        lat: row.lat,
        lng: row.lng,
        refId: row.refId,
        payload: decodedPayload,
        sig: row.sig,
        ttl: row.ttl,
        hops: row.hops,
      ),
      receivedAt: row.receivedAt,
      geohash: row.geohash,
      trust: trust,
      isLocal: row.isLocal != 0,
    );
  }
}

