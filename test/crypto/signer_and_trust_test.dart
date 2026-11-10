import 'dart:convert';
import 'dart:typed_data';

import 'package:mesh_rescue/crypto/signer.dart';
import 'package:mesh_rescue/crypto/trust_service.dart';
import 'package:mesh_rescue/engine/canonical_json.dart';
import 'package:mesh_rescue/engine/models/envelope.dart';
import 'package:mesh_rescue/engine/models/enums.dart';
import 'package:test/test.dart';

void main() {
  group('Ed25519Signer and TrustService', () {
    late Ed25519Signer signer;

    setUp(() {
      signer = Ed25519Signer();
    });

    test('signs and verifies envelope; tampering fails verification', () async {
      final alice = await signer.loadKeyPairFromSeed(List<int>.filled(32, 7));
      final bob = await signer.loadKeyPairFromSeed(List<int>.filled(32, 9));

      final unsigned = Envelope(
        id: 'msg-1',
        type: MessageType.sos,
        origin: alice.origin,
        originPub: alice.publicKeyBase64,
        ts: 1731200000,
        lat: 21.4669,
        lng: 83.9812,
        refId: null,
        payload: const {'category': 'trapped', 'people': 3, 'note': 'roof'},
        sig: '',
        ttl: 10,
        hops: 0,
      );

      final signed = await signer.signEnvelope(unsigned, alice);
      expect(await signer.verifyEnvelope(signed), isTrue);
      expect(
        await signer.matchesOrigin(signed.origin, signed.originPub),
        isTrue,
      );

      // Tamper payload
      final tamperedPayload = Envelope(
        id: signed.id,
        type: signed.type,
        origin: signed.origin,
        originPub: signed.originPub,
        ts: signed.ts,
        lat: signed.lat,
        lng: signed.lng,
        refId: signed.refId,
        payload: const {'category': 'trapped', 'people': 99, 'note': 'roof'},
        sig: signed.sig,
        ttl: signed.ttl,
        hops: signed.hops,
      );
      expect(await signer.verifyEnvelope(tamperedPayload), isFalse);

      // Tamper coordinates
      final tamperedCoords = Envelope(
        id: signed.id,
        type: signed.type,
        origin: signed.origin,
        originPub: signed.originPub,
        ts: signed.ts,
        lat: 22.0,
        lng: signed.lng,
        refId: signed.refId,
        payload: signed.payload,
        sig: signed.sig,
        ttl: signed.ttl,
        hops: signed.hops,
      );
      expect(await signer.verifyEnvelope(tamperedCoords), isFalse);

      // Wrong public key
      final wrongKey = Envelope(
        id: signed.id,
        type: signed.type,
        origin: bob.origin,
        originPub: bob.publicKeyBase64,
        ts: signed.ts,
        lat: signed.lat,
        lng: signed.lng,
        refId: signed.refId,
        payload: signed.payload,
        sig: signed.sig,
        ttl: signed.ttl,
        hops: signed.hops,
      );
      expect(await signer.verifyEnvelope(wrongKey), isFalse);

      // Origin / originPub mismatch
      expect(
        await signer.matchesOrigin(bob.origin, alice.publicKeyBase64),
        isFalse,
      );
    });

    test('malformed base64 or wrong byte lengths return false without throwing', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      expect(
        await signer.verifyBytes(
          bytes,
          signatureBase64: 'not-base64!!!',
          publicKeyBase64: 'not-base64!!!',
        ),
        isFalse,
      );
      expect(
        await signer.verifyBytes(
          bytes,
          signatureBase64: base64Encode(List<int>.filled(10, 1)),
          publicKeyBase64: base64Encode(List<int>.filled(32, 2)),
        ),
        isFalse,
      );
      expect(
        await signer.matchesOrigin('deadbeef', base64Encode([1, 2, 3])),
        isFalse,
      );
    });

    test('assigns VERIFIED_RESPONDER vs SIGNED_PEER vs UNVERIFIED shelter', () async {
      final responder = await signer.loadKeyPairFromSeed(List<int>.filled(32, 1));
      final attacker = await signer.loadKeyPairFromSeed(List<int>.filled(32, 2));

      final trust = TrustService([
        TrustedResponder(name: 'Control Room', pub: responder.publicKeyBase64),
      ]);

      expect(
        trust.evaluateTrust(
          type: MessageType.shelter,
          originPub: responder.publicKeyBase64,
          signatureValid: true,
        ),
        TrustTier.verifiedResponder,
      );
      expect(
        trust.evaluateTrust(
          type: MessageType.shelter,
          originPub: attacker.publicKeyBase64,
          signatureValid: true,
        ),
        TrustTier.unverified,
      );
      expect(
        trust.evaluateTrust(
          type: MessageType.sos,
          originPub: attacker.publicKeyBase64,
          signatureValid: true,
        ),
        TrustTier.signedPeer,
      );

      // Roundtrip JSON parsing for trusted_responders.json
      final jsonStr = jsonEncode({
        'version': 1,
        'responders': [
          {'name': 'Control Room', 'pub': responder.publicKeyBase64},
        ],
      });
      final parsed = TrustService.fromJsonString(jsonStr);
      expect(parsed.isTrustedResponderPub(responder.publicKeyBase64), isTrue);
      expect(parsed.responderNameForPub(responder.publicKeyBase64), 'Control Room');
      expect(canonicalJson({'ok': true}), '{"ok":true}');
    });
  });
}

