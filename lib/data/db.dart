import 'package:drift/drift.dart';

part 'db.g.dart';

@DataClassName('MessageRow')
@TableIndex(name: 'idx_messages_type_recv', columns: {#type, #receivedAt})
@TableIndex(name: 'idx_messages_geohash', columns: {#geohash})
@TableIndex(name: 'idx_messages_ref', columns: {#refId})
class Messages extends Table {
  @override
  String get tableName => 'messages';

  TextColumn get id => text()();
  TextColumn get type => text()();
  TextColumn get origin => text()();
  TextColumn get originPub => text().named('origin_pub')();
  IntColumn get ts => integer()();
  IntColumn get receivedAt => integer().named('received_at')();
  RealColumn get lat => real().nullable()();
  RealColumn get lng => real().nullable()();
  TextColumn get geohash => text().nullable()();
  IntColumn get ttl => integer()();
  IntColumn get hops => integer().withDefault(const Constant(0))();
  TextColumn get refId => text().named('ref_id').nullable()();
  TextColumn get payload => text()();
  TextColumn get sig => text()();
  TextColumn get trust => text()();
  IntColumn get isLocal => integer().named('is_local').withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('OutboxRow')
class OutboxEntries extends Table {
  @override
  String get tableName => 'outbox';

  TextColumn get messageId => text().named('message_id')();
  TextColumn get peerId => text().named('peer_id')();
  IntColumn get sentAt => integer().named('sent_at').nullable()();

  @override
  Set<Column<Object>> get primaryKey => {messageId, peerId};
}

@DataClassName('SettingRow')
class AppSettings extends Table {
  @override
  String get tableName => 'settings';

  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(tables: [Messages, OutboxEntries, AppSettings])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;
}

