import 'dart:convert';
import 'dart:typed_data';

import 'package:mesh_rescue/crypto/signer.dart';
import 'package:mesh_rescue/crypto/trust_service.dart';
import 'package:mesh_rescue/data/message_store.dart';
import 'package:mesh_rescue/engine/clock.dart';
import 'package:mesh_rescue/engine/mesh_engine.dart';
import 'package:mesh_rescue/engine/models/envelope.dart';
import 'package:mesh_rescue/engine/models/enums.dart';
import 'package:mesh_rescue/engine/models/frame.dart';
import 'package:mesh_rescue/engine/models/payloads.dart';
import 'package:mesh_rescue/transport/sim/sim_transport.dart';
import 'package:test/test.dart';

Future<Envelope> _makeSignedEnvelope(
  Ed25519Signer signer,
  IdentityKeyPair identity, {
  String id = '11111111-1111-4111-8111-111111111111',
  MessageType type = MessageType.sos,
  int ts = 1731200000,
  double? lat = 21.4669,
  double? lng = 83.9812,
  String? refId,
  Map<String, Object?>? payload,
  int ttl = 10,
  int hops = 0,
}) async {
  final unsigned = Envelope(
    id: id,
    type: type,
    origin: identity.origin,
    originPub: identity.publicKeyBase64,
    ts: ts,
    lat: lat,
    lng: lng,
    refId: refId,
    payload: payload ??
        const {
          'category': 'trapped',
          'people': 2,
          'note': 'help',
        },
    sig: '',
    ttl: ttl,
    hops: hops,
  );
  return signer.signEnvelope(unsigned, identity);
}

void main() {
  group('MeshEngine pipeline, outbox, and rate limiting', () {
    late FakeClock clock;
    late Ed25519Signer signer;
    late IdentityKeyPair localId;
    late IdentityKeyPair peerId;
    late IdentityKeyPair responderId;
    late TrustService trustService;
    late InMemoryMessageStore store;
    late List<({String to, Uint8List bytes})> sentFrames;
    late List<String> disconnectedPeers;
    late SimTransport transport;
    late MeshEngine engine;

    setUp(() async {
      clock = FakeClock.fromSeconds(1731200000);
      signer = Ed25519Signer();
      localId = await signer.loadKeyPairFromSeed(List<int>.filled(32, 1));
      peerId = await signer.loadKeyPairFromSeed(List<int>.filled(32, 2));
      responderId = await signer.loadKeyPairFromSeed(List<int>.filled(32, 3));
      trustService = TrustService([
        TrustedResponder(name: 'Demo Control', pub: responderId.publicKeyBase64),
      ]);
      store = InMemoryMessageStore();
      sentFrames = [];
      disconnectedPeers = [];
      transport = SimTransport(
        deviceId: localId.origin,
        onSend: (from, to, bytes) async {
          sentFrames.add((to: to, bytes: bytes));
        },
        onDisconnectRequested: (from, to) async {
          disconnectedPeers.add(to);
        },
      );
      engine = MeshEngine(
        transport: transport,
        store: store,
        signer: signer,
        identity: localId,
        trustService: trustService,
        clock: clock,
      );
      await engine.start();
    });

    tearDown(() async {
      await engine.dispose();
      await transport.dispose();
    });

    test('validation drops malformed frames with exact reason codes', () async {
      final drops = <DropReason>[];
      final sub = engine.onDrop.listen((e) => drops.add(e.reason));

      // 1. BAD_FRAME: empty, oversized, bad JSON
      await engine.receiveFrame('p1', Uint8List(0));
      await engine.receiveFrame('p1', Uint8List(FrameCodec.maxFrameBytes + 1));
      await engine.receiveFrame(
        'p1',
        Uint8List.fromList([FrameType.msg.byteValue, ...utf8.encode('{bad')]),
      );

      // 2. BAD_SCHEMA: missing fields
      await engine.receiveFrame(
        'p2',
        Uint8List.fromList([
          FrameType.msg.byteValue,
          ...utf8.encode(jsonEncode({'id': 'x'})),
        ]),
      );

      // 3. BAD_PAYLOAD: unknown type and invalid severity
      await engine.receiveFrame(
        'p2',
        Uint8List.fromList([
          FrameType.msg.byteValue,
          ...utf8.encode(jsonEncode({
            'id': 'm1',
            'type': 'NOPE',
            'origin': peerId.origin,
            'originPub': peerId.publicKeyBase64,
            'ts': 1731200000,
            'lat': 21.0,
            'lng': 83.0,
            'refId': null,
            'payload': {},
            'sig': 'sig',
            'ttl': 5,
            'hops': 0,
          })),
        ]),
      );

      // 4. BAD_COORDS
      await engine.receiveFrame(
        'p2',
        Uint8List.fromList([
          FrameType.msg.byteValue,
          ...utf8.encode(jsonEncode({
            'id': 'm2',
            'type': 'HAZARD',
            'origin': peerId.origin,
            'originPub': peerId.publicKeyBase64,
            'ts': 1731200000,
            'lat': 95.0,
            'lng': 83.0,
            'refId': null,
            'payload': {'kind': 'flood', 'severity': 3, 'note': ''},
            'sig': 'sig',
            'ttl': 5,
            'hops': 0,
          })),
        ]),
      );

      // 5. BAD_ORIGIN
      final validSigned = await _makeSignedEnvelope(signer, peerId);
      final badOriginJson = validSigned.toJson()..['origin'] = '00000000';
      await engine.receiveFrame(
        'p3',
        Uint8List.fromList([
          FrameType.msg.byteValue,
          ...utf8.encode(jsonEncode(badOriginJson)),
        ]),
      );

      // 6. BAD_SIG
      final badSigJson = validSigned.toJson()
        ..['sig'] = base64Encode(List<int>.filled(64, 5));
      await engine.receiveFrame(
        'p3',
        Uint8List.fromList([
          FrameType.msg.byteValue,
          ...utf8.encode(jsonEncode(badSigJson)),
        ]),
      );

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(drops, [
        DropReason.badFrame,
        DropReason.badFrame,
        DropReason.badFrame,
        DropReason.badSchema,
        DropReason.badPayload,
        DropReason.badCoords,
        DropReason.badOrigin,
        DropReason.badSig,
      ]);
      expect(await store.countMessages(), 0);
    });

    test('dedup, TTL clamp to 10, TTL decrement, stop at 0, and never echo back', () async {
      transport.simulatePeerConnected('peerA');
      transport.simulatePeerConnected('peerB');
      await Future<void>.delayed(Duration.zero);
      sentFrames.clear();

      // Oversized TTL 99 should be clamped to 10, then stored as 9 with hops 1.
      final env = await _makeSignedEnvelope(
        signer,
        peerId,
        id: 'ttl-clamp-1',
        ttl: 99,
        hops: 0,
      );
      final frameBytes = FrameCodec.encode(MsgFrame(envelope: env));
      final accepted = await engine.receiveFrame('peerA', frameBytes);
      expect(accepted, isNotNull);
      expect(accepted!.envelope.ttl, 9);
      expect(accepted.envelope.hops, 1);

      // Duplicate delivery from peerB must be dropped as DUPLICATE.
      final dup = await engine.receiveFrame('peerB', frameBytes);
      expect(dup, isNull);
      expect(engine.dropCounts[DropReason.duplicate], 1);

      await engine.outbox.flush(engine.connectedPeers);
      final msgSent = sentFrames
          .where((f) => FrameCodec.decode(f.bytes) is MsgFrame)
          .toList();
      // peerA was the sender; peerB already sent the duplicate so both know it!
      expect(msgSent, isEmpty);

      // New peerC connects -> receives forwarded message once only.
      sentFrames.clear();
      transport.simulatePeerConnected('peerC');
      await Future<void>.delayed(Duration.zero);
      await engine.outbox.flush(engine.connectedPeers);
      await engine.outbox.flush(engine.connectedPeers);

      final toPeerC = sentFrames
          .where((f) => f.to == 'peerC' && FrameCodec.decode(f.bytes) is MsgFrame)
          .toList();
      expect(toPeerC.length, 1);
      final forwarded = (FrameCodec.decode(toPeerC.first.bytes) as MsgFrame).envelope;
      expect(forwarded.ttl, 9);
      expect(forwarded.hops, 1);

      // Message arriving with ttl == 1 is stored for display, never forwarded.
      final edgeEnv = await _makeSignedEnvelope(
        signer,
        peerId,
        id: 'ttl-edge-1',
        ttl: 1,
        hops: 9,
      );
      sentFrames.clear();
      final edgeStored = await engine.receiveFrame(
        'peerA',
        FrameCodec.encode(MsgFrame(envelope: edgeEnv)),
      );
      expect(edgeStored, isNotNull);
      expect(edgeStored!.envelope.ttl, 0);
      expect(edgeStored.envelope.hops, 10);
      await engine.outbox.flush(engine.connectedPeers);
      expect(
        sentFrames.where((f) => FrameCodec.decode(f.bytes) is MsgFrame),
        isEmpty,
      );
    });

    test('outbox sends in strict priority order: SOS > ACK > SHELTER > HAZARD', () async {
      // Publish lowest priority first while disconnected.
      await engine.publishHazard(
        payload: const HazardPayload(kind: HazardKind.flood, severity: 3),
        lat: 21.4,
        lng: 83.9,
      );
      clock.advanceSeconds(1);
      await engine.publishShelter(
        payload: const ShelterPayload(
          key: 's1',
          name: 'School',
          status: ShelterStatus.open,
          capacity: 100,
          services: ['water'],
          seq: 1,
        ),
        lat: 21.4,
        lng: 83.9,
        signingIdentity: responderId,
      );
      clock.advanceSeconds(1);
      final sos = await engine.publishSos(
        payload: const SosPayload(category: SosCategory.medical, people: 1),
        lat: 21.4,
        lng: 83.9,
      );
      clock.advanceSeconds(1);
      await engine.publishAck(
        sosId: sos.id,
        payload: const AckPayload(status: AckStatus.received),
        signingIdentity: responderId,
      );

      transport.simulatePeerConnected('peer1');
      await Future<void>.delayed(Duration.zero);
      // 1st flush ran automatically on connect (SOS), flush remaining 3.
      await engine.outbox.flush(engine.connectedPeers);
      await engine.outbox.flush(engine.connectedPeers);
      await engine.outbox.flush(engine.connectedPeers);

      final sentTypes = sentFrames
          .map((f) => FrameCodec.decode(f.bytes))
          .whereType<MsgFrame>()
          .map((m) => m.envelope.type)
          .toList();
      expect(sentTypes, [
        MessageType.sos,
        MessageType.ack,
        MessageType.shelter,
        MessageType.hazard,
      ]);
    });

    test('rate limiter drops 11th message within 60s and refills after 60s', () async {
      for (var i = 0; i < 10; i++) {
        final env = await _makeSignedEnvelope(
          signer,
          peerId,
          id: 'rate-$i',
          ts: clock.nowSeconds(),
        );
        final res = await engine.receiveFrame(
          'peerA',
          FrameCodec.encode(MsgFrame(envelope: env)),
        );
        expect(res, isNotNull);
      }

      final eleventh = await _makeSignedEnvelope(
        signer,
        peerId,
        id: 'rate-10',
        ts: clock.nowSeconds(),
      );
      final dropped = await engine.receiveFrame(
        'peerA',
        FrameCodec.encode(MsgFrame(envelope: eleventh)),
      );
      expect(dropped, isNull);
      expect(engine.dropCounts[DropReason.rateLimited], 1);

      clock.advanceSeconds(60);
      final afterRefill = await _makeSignedEnvelope(
        signer,
        peerId,
        id: 'rate-11',
        ts: clock.nowSeconds(),
      );
      expect(
        await engine.receiveFrame(
          'peerA',
          FrameCodec.encode(MsgFrame(envelope: afterRefill)),
        ),
        isNotNull,
      );
    });

    test('rejects fake non-responder ACK and allows origin CANCELLED ACK', () async {
      final sos = await _makeSignedEnvelope(
        signer,
        peerId,
        id: 'sos-target',
      );
      expect(
        await engine.receiveFrame(
          'peerA',
          FrameCodec.encode(MsgFrame(envelope: sos)),
        ),
        isNotNull,
      );

      // Random peer tries to forge RECEIVED ACK -> UNAUTHORIZED
      final intruder = await signer.loadKeyPairFromSeed(List<int>.filled(32, 99));
      final fakeAck = await _makeSignedEnvelope(
        signer,
        intruder,
        id: 'fake-ack-1',
        type: MessageType.ack,
        lat: null,
        lng: null,
        refId: 'sos-target',
        payload: const {'status': 'RECEIVED', 'note': 'fake'},
      );
      expect(
        await engine.receiveFrame(
          'peerA',
          FrameCodec.encode(MsgFrame(envelope: fakeAck)),
        ),
        isNull,
      );
      expect(engine.dropCounts[DropReason.unauthorized], 1);

      // Intruder tries to CANCEL someone else's SOS -> UNAUTHORIZED
      final fakeCancel = await _makeSignedEnvelope(
        signer,
        intruder,
        id: 'fake-cancel-1',
        type: MessageType.ack,
        lat: null,
        lng: null,
        refId: 'sos-target',
        payload: const {'status': 'CANCELLED', 'note': 'safe'},
      );
      expect(
        await engine.receiveFrame(
          'peerA',
          FrameCodec.encode(MsgFrame(envelope: fakeCancel)),
        ),
        isNull,
      );
      expect(engine.dropCounts[DropReason.unauthorized], 2);

      // Original SOS origin cancels -> accepted
      final realCancel = await _makeSignedEnvelope(
        signer,
        peerId,
        id: 'real-cancel-1',
        type: MessageType.ack,
        lat: null,
        lng: null,
        refId: 'sos-target',
        payload: const {'status': 'CANCELLED', 'note': 'safe now'},
      );
      expect(
        await engine.receiveFrame(
          'peerA',
          FrameCodec.encode(MsgFrame(envelope: realCancel)),
        ),
        isNotNull,
      );
    });

    test('local un-ACKed SOS rebroadcasts every 30s (60s battery saver) until ACKed', () async {
      transport.simulatePeerConnected('peer1');
      await Future<void>.delayed(Duration.zero);

      final sos = await engine.publishSos(
        payload: const SosPayload(category: SosCategory.trapped, people: 2),
        lat: 21.4,
        lng: 83.9,
      );
      sentFrames.clear();

      // At +29s -> no rebroadcast yet
      clock.advanceSeconds(29);
      await engine.tick();
      expect(
        sentFrames.where((f) => FrameCodec.decode(f.bytes) is MsgFrame),
        isEmpty,
      );

      // At +30s -> rebroadcast fires because peer1 hasn't confirmed via INV
      clock.advanceSeconds(1);
      await engine.tick();
      expect(
        sentFrames.where((f) => FrameCodec.decode(f.bytes) is MsgFrame).length,
        1,
      );

      // Once responder ACK arrives, rebroadcast stops permanently
      sentFrames.clear();
      final ack = await _makeSignedEnvelope(
        signer,
        responderId,
        id: 'ack-for-local',
        type: MessageType.ack,
        lat: null,
        lng: null,
        refId: sos.id,
        payload: const {'status': 'RECEIVED', 'note': ''},
      );
      await engine.receiveFrame(
        'peer1',
        FrameCodec.encode(MsgFrame(envelope: ack)),
      );
      clock.advanceSeconds(60);
      await engine.tick();
      expect(
        sentFrames.where((f) => FrameCodec.decode(f.bytes) is MsgFrame),
        isEmpty,
      );
    });

    test('5 invalid frames in 60s disconnects and blocks abusive peer', () async {
      transport.simulatePeerConnected('badPeer');
      await Future<void>.delayed(Duration.zero);

      for (var i = 0; i < 5; i++) {
        await engine.receiveFrame('badPeer', Uint8List(0));
      }
      expect(disconnectedPeers, contains('badPeer'));
      expect(engine.abuseTracker.isBlocked('badPeer'), isTrue);
    });

    test('InMemoryMessageStore evicts expired and low-priority before SOS and verified shelters', () async {
      final bounded = InMemoryMessageStore(maxMessages: 2);
      const t0 = 1731200000;

      final sosEnv = await _makeSignedEnvelope(signer, peerId, id: 'sos-keep', ts: t0);
      final hazEnv = await _makeSignedEnvelope(
        signer,
        peerId,
        id: 'haz-drop',
        type: MessageType.hazard,
        ts: t0 + 1,
        payload: const {'kind': 'flood', 'severity': 2, 'note': ''},
      );
      final forgedShelterEnv = await _makeSignedEnvelope(
        signer,
        peerId,
        id: 'shelter-forged-drop',
        type: MessageType.shelter,
        ts: t0 + 2,
        payload: const {
          'key': 'k',
          'name': 'Fake',
          'status': 'OPEN',
          'capacity': 10,
          'services': ['water'],
          'seq': 1,
        },
      );

      await bounded.saveMessage(
        StoredMessage(
          envelope: sosEnv,
          receivedAt: t0,
          geohash: 'tgcc123',
          trust: TrustTier.signedPeer,
          isLocal: false,
        ),
        nowSeconds: t0,
      );
      await bounded.saveMessage(
        StoredMessage(
          envelope: hazEnv,
          receivedAt: t0 + 1,
          geohash: 'tgcc123',
          trust: TrustTier.signedPeer,
          isLocal: false,
        ),
        nowSeconds: t0 + 1,
      );
      await bounded.saveMessage(
        StoredMessage(
          envelope: forgedShelterEnv,
          receivedAt: t0 + 2,
          geohash: 'tgcc123',
          trust: TrustTier.unverified,
          isLocal: false,
        ),
        nowSeconds: t0 + 2,
      );

      // Cap=2 should evict the UNVERIFIED forged shelter first, keeping SOS & hazard.
      expect(await bounded.countMessages(), 2);
      expect(await bounded.hasMessage('sos-keep'), isTrue);
      expect(await bounded.hasMessage('haz-drop'), isTrue);
      expect(await bounded.hasMessage('shelter-forged-drop'), isFalse);
    });
  });
}
