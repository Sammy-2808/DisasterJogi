import 'dart:io';

import 'package:drift/native.dart';
import 'package:mesh_rescue/crypto/demo_responder_key.dart';
import 'package:mesh_rescue/crypto/signer.dart';
import 'package:mesh_rescue/crypto/trust_service.dart';
import 'package:mesh_rescue/data/db.dart';
import 'package:mesh_rescue/data/drift_message_store.dart';
import 'package:mesh_rescue/data/message_store.dart';
import 'package:mesh_rescue/engine/models/envelope.dart';
import 'package:mesh_rescue/engine/models/enums.dart';
import 'package:test/test.dart';

void main() {
  group('DriftMessageStore and DemoResponderKey', () {
    late AppDatabase db;
    late DriftMessageStore store;
    late Ed25519Signer signer;
    late IdentityKeyPair peerId;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      store = DriftMessageStore(db, maxMessages: 3);
      signer = Ed25519Signer();
      peerId = await signer.loadKeyPairFromSeed(List<int>.filled(32, 5));
    });

    tearDown(() async {
      await db.close();
    });

    Future<StoredMessage> makeMsg({
      required String id,
      required MessageType type,
      required int recv,
      TrustTier trust = TrustTier.signedPeer,
      Map<String, Object?>? payload,
      int ttl = 6,
    }) async {
      final env = await signer.signEnvelope(
        Envelope(
          id: id,
          type: type,
          origin: peerId.origin,
          originPub: peerId.publicKeyBase64,
          ts: recv,
          lat: 21.46,
          lng: 83.98,
          refId: null,
          payload: payload ??
              const {'category': 'trapped', 'people': 2, 'note': 'help'},
          sig: '',
          ttl: ttl,
          hops: 1,
        ),
        peerId,
      );
      return StoredMessage(
        envelope: env,
        receivedAt: recv,
        geohash: 'tgcu123',
        trust: trust,
        isLocal: false,
      );
    }

    test('persists messages, outbox tracking, settings, and evicts low-priority first', () async {
      const t0 = 1731200000;
      await store.saveMessage(
        await makeMsg(id: 'sos-1', type: MessageType.sos, recv: t0),
        nowSeconds: t0,
      );
      await store.saveMessage(
        await makeMsg(
          id: 'haz-1',
          type: MessageType.hazard,
          recv: t0 + 1,
          payload: const {'kind': 'flood', 'severity': 2, 'note': ''},
        ),
        nowSeconds: t0 + 1,
      );
      await store.saveMessage(
        await makeMsg(
          id: 'sh-verified',
          type: MessageType.shelter,
          recv: t0 + 2,
          trust: TrustTier.verifiedResponder,
          payload: const {
            'key': 's1',
            'name': 'School',
            'status': 'OPEN',
            'capacity': 100,
            'services': ['water'],
            'seq': 1,
          },
        ),
        nowSeconds: t0 + 2,
      );
      // 4th message forces eviction at cap=3; peer hazard should be evicted before SOS/verified shelter.
      await store.saveMessage(
        await makeMsg(id: 'sos-2', type: MessageType.sos, recv: t0 + 3),
        nowSeconds: t0 + 3,
      );

      expect(await store.countMessages(), 3);
      expect(await store.hasMessage('haz-1'), isFalse);
      expect(await store.hasMessage('sos-1'), isTrue);
      expect(await store.hasMessage('sh-verified'), isTrue);

      await store.markSentTo('sos-1', 'peerB', t0 + 10);
      expect(await store.hasBeenSentTo('sos-1', 'peerB'), isTrue);
      final unsentForB = await store.getUnsentForPeer('peerB', nowSeconds: t0 + 10);
      expect(unsentForB.map((m) => m.id), isNot(contains('sos-1')));
      expect(unsentForB.first.type, MessageType.sos);

      // Settings roundtrip
      await store.setSetting('battery_saver', 'true');
      expect(await store.getSetting('battery_saver'), 'true');
    });

    test('expiry purges messages based on local received_at', () async {
      const t0 = 1731200000;
      await store.saveMessage(
        await makeMsg(
          id: 'haz-old',
          type: MessageType.hazard,
          recv: t0,
          payload: const {'kind': 'fire', 'severity': 3, 'note': ''},
        ),
        nowSeconds: t0,
      );
      expect(await store.purgeExpired(t0 + 11 * 3600), 0);
      expect(await store.purgeExpired(t0 + 12 * 3600), 1);
      expect(await store.countMessages(), 0);
    });

    test('DemoResponderKey matches assets/trusted_responders.json', () async {
      expect(await DemoResponderKey.unlockWithPin('0000'), isNull);
      final demoId = await DemoResponderKey.unlockWithPin(DemoResponderKey.demoPin);
      expect(demoId, isNotNull);

      final assetJson = await File('assets/trusted_responders.json').readAsString();
      final trust = TrustService.fromJsonString(assetJson);
      expect(trust.isTrustedResponderPub(demoId!.publicKeyBase64), isTrue);
    });
  });
}

