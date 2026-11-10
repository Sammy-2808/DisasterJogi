import 'package:mesh_rescue/crypto/signer.dart';
import 'package:mesh_rescue/crypto/trust_service.dart';
import 'package:mesh_rescue/data/message_store.dart';
import 'package:mesh_rescue/domain/geo.dart';
import 'package:mesh_rescue/domain/hazard_cluster.dart';
import 'package:mesh_rescue/domain/shelter_logic.dart';
import 'package:mesh_rescue/domain/sos_state.dart';
import 'package:mesh_rescue/engine/models/envelope.dart';
import 'package:mesh_rescue/engine/models/enums.dart';
import 'package:test/test.dart';

Future<StoredMessage> _stored(
  Ed25519Signer signer,
  IdentityKeyPair id, {
  required String msgId,
  required MessageType type,
  required int receivedAt,
  double? lat = 21.4669,
  double? lng = 83.9812,
  String? refId,
  required Map<String, Object?> payload,
  TrustTier trust = TrustTier.signedPeer,
}) async {
  final unsigned = Envelope(
    id: msgId,
    type: type,
    origin: id.origin,
    originPub: id.publicKeyBase64,
    ts: receivedAt,
    lat: lat,
    lng: lng,
    refId: refId,
    payload: payload,
    sig: '',
    ttl: type.defaultTtl,
    hops: 0,
  );
  final signed = await signer.signEnvelope(unsigned, id);
  return StoredMessage(
    envelope: signed,
    receivedAt: receivedAt,
    geohash: (lat != null && lng != null) ? encodeGeohash7(lat, lng) : null,
    trust: trust,
    isLocal: false,
  );
}

void main() {
  late Ed25519Signer signer;
  late IdentityKeyPair civilianA;
  late IdentityKeyPair civilianB;
  late IdentityKeyPair responder;
  late TrustService trust;

  setUp(() async {
    signer = Ed25519Signer();
    civilianA = await signer.loadKeyPairFromSeed(List<int>.filled(32, 1));
    civilianB = await signer.loadKeyPairFromSeed(List<int>.filled(32, 2));
    responder = await signer.loadKeyPairFromSeed(List<int>.filled(32, 3));
    trust = TrustService([
      TrustedResponder(name: 'Control', pub: responder.publicKeyBase64),
    ]);
  });

  group('Geo utilities', () {
    test('geohash-7, haversine distance, and bearing work as expected', () {
      final hash = encodeGeohash7(21.4669, 83.9812);
      expect(hash.length, 7);

      // 1 degree latitude ~ 111.19 km
      final dist = haversineDistanceMeters(0.0, 0.0, 1.0, 0.0);
      expect(dist, closeTo(111195, 250));

      // Due north -> 0 deg; due east -> ~90 deg
      expect(initialBearingDegrees(0.0, 0.0, 1.0, 0.0), closeTo(0.0, 0.01));
      expect(initialBearingDegrees(0.0, 0.0, 0.0, 1.0), closeTo(90.0, 0.01));
    });
  });

  group('SOS lifecycle derivation', () {
    test('ACTIVE -> ACKNOWLEDGED -> RESOLVED and rejects fake ACK', () async {
      const t0 = 1731200000;
      final sos = await _stored(
        signer,
        civilianA,
        msgId: 'sos-1',
        type: MessageType.sos,
        receivedAt: t0,
        payload: const {'category': 'trapped', 'people': 3, 'note': ''},
      );

      // Initially ACTIVE
      expect(
        deriveSosState(
          sos: sos,
          candidateAcks: const [],
          trustService: trust,
          nowSeconds: t0 + 60,
        ).status,
        SosStatus.active,
      );

      // Fake ACK from untrusted civilianB ignored -> still ACTIVE
      final fakeAck = await _stored(
        signer,
        civilianB,
        msgId: 'ack-fake',
        type: MessageType.ack,
        receivedAt: t0 + 100,
        lat: null,
        lng: null,
        refId: 'sos-1',
        payload: const {'status': 'RECEIVED', 'note': 'fake'},
      );
      expect(
        deriveSosState(
          sos: sos,
          candidateAcks: [fakeAck],
          trustService: trust,
          nowSeconds: t0 + 120,
        ).status,
        SosStatus.active,
      );

      // Responder RECEIVED -> ACKNOWLEDGED
      final ackRecv = await _stored(
        signer,
        responder,
        msgId: 'ack-1',
        type: MessageType.ack,
        receivedAt: t0 + 200,
        lat: null,
        lng: null,
        refId: 'sos-1',
        payload: const {'status': 'RECEIVED', 'note': 'Unit 2'},
        trust: TrustTier.verifiedResponder,
      );
      final afterRecv = deriveSosState(
        sos: sos,
        candidateAcks: [fakeAck, ackRecv],
        trustService: trust,
        nowSeconds: t0 + 250,
      );
      expect(afterRecv.status, SosStatus.acknowledged);
      expect(afterRecv.ackStatus, AckStatus.received);

      // Origin CANCELLED ("I'm safe") -> RESOLVED
      final cancel = await _stored(
        signer,
        civilianA,
        msgId: 'ack-2',
        type: MessageType.ack,
        receivedAt: t0 + 300,
        lat: null,
        lng: null,
        refId: 'sos-1',
        payload: const {'status': 'CANCELLED', 'note': 'Safe'},
      );
      expect(
        deriveSosState(
          sos: sos,
          candidateAcks: [ackRecv, cancel],
          trustService: trust,
          nowSeconds: t0 + 350,
        ).status,
        SosStatus.resolved,
      );

      // Un-resolved SOS expires after 24h local receivedAt
      expect(
        deriveSosState(
          sos: sos,
          candidateAcks: const [],
          trustService: trust,
          nowSeconds: t0 + ExpiryDurations.sosSeconds,
        ).status,
        SosStatus.expired,
      );
    });
  });

  group('Hazard clustering and confirmation', () {
    test('merges same kind + geohash-7 and promotes at 2+ distinct origins', () async {
      const t0 = 1731200000;
      final h1 = await _stored(
        signer,
        civilianA,
        msgId: 'h1',
        type: MessageType.hazard,
        receivedAt: t0,
        lat: 21.46690,
        lng: 83.98120,
        payload: const {'kind': 'flood', 'severity': 3, 'note': 'knee deep'},
      );
      final h2 = await _stored(
        signer,
        civilianB,
        msgId: 'h2',
        type: MessageType.hazard,
        receivedAt: t0 + 120,
        lat: 21.46691,
        lng: 83.98121,
        refId: 'h1',
        payload: const {'kind': 'flood', 'severity': 4, 'note': 'confirmed'},
      );

      final single = clusterHazards([h1], nowSeconds: t0 + 60);
      expect(single.length, 1);
      expect(single.first.isConfirmed, isFalse);
      expect(single.first.confirmationLabel, 'REPORTED');

      final both = clusterHazards([h1, h2], nowSeconds: t0 + 180);
      expect(both.length, 1);
      expect(both.first.isConfirmed, isTrue);
      expect(both.first.distinctOriginsCount, 2);
      expect(both.first.maxSeverity, 4);

      // h1 gets +6h lifetime bonus (18h total) because civilianB confirmed refId='h1'
      final after13h = clusterHazards([h1, h2], nowSeconds: t0 + 13 * 3600);
      expect(after13h.length, 1);
      expect(after13h.first.reports.length, 2);
    });
  });

  group('Shelter supersession and verification', () {
    test('highest seq wins for (origin, key), CLOSED hides, forged hidden by default', () async {
      const t0 = 1731200000;
      final s1 = await _stored(
        signer,
        responder,
        msgId: 'sh-1',
        type: MessageType.shelter,
        receivedAt: t0,
        payload: const {
          'key': 'school-1',
          'name': 'High School',
          'status': 'OPEN',
          'capacity': 200,
          'services': ['water'],
          'seq': 1,
        },
        trust: TrustTier.verifiedResponder,
      );
      final s2 = await _stored(
        signer,
        responder,
        msgId: 'sh-2',
        type: MessageType.shelter,
        receivedAt: t0 + 60,
        payload: const {
          'key': 'school-1',
          'name': 'High School',
          'status': 'FULL',
          'capacity': 200,
          'services': ['water', 'medical'],
          'seq': 2,
        },
        trust: TrustTier.verifiedResponder,
      );
      final forged = await _stored(
        signer,
        civilianA,
        msgId: 'sh-forged',
        type: MessageType.shelter,
        receivedAt: t0 + 90,
        payload: const {
          'key': 'fake-camp',
          'name': 'Fake Camp',
          'status': 'OPEN',
          'capacity': 999,
          'services': ['food'],
          'seq': 1,
        },
        trust: TrustTier.unverified,
      );

      final verifiedOnly = resolveShelters(
        [s1, s2, forged],
        nowSeconds: t0 + 120,
      );
      expect(verifiedOnly.length, 1);
      expect(verifiedOnly.first.seq, 2);
      expect(verifiedOnly.first.payload.status, ShelterStatus.full);
      expect(verifiedOnly.first.isVerified, isTrue);

      final withUnverified = resolveShelters(
        [s1, s2, forged],
        nowSeconds: t0 + 120,
        includeUnverified: true,
      );
      expect(withUnverified.length, 2);
      expect(withUnverified.first.isVerified, isTrue);
      expect(withUnverified.last.isVerified, isFalse);

      // CLOSED supersedes OPEN/FULL and hides listing
      final s3Closed = await _stored(
        signer,
        responder,
        msgId: 'sh-3',
        type: MessageType.shelter,
        receivedAt: t0 + 200,
        payload: const {
          'key': 'school-1',
          'name': 'High School',
          'status': 'CLOSED',
          'capacity': 200,
          'services': ['water'],
          'seq': 3,
        },
        trust: TrustTier.verifiedResponder,
      );
      expect(
        resolveShelters([s1, s2, s3Closed], nowSeconds: t0 + 250),
        isEmpty,
      );
    });
  });
}

