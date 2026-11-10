import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:mesh_rescue/engine/canonical_json.dart';
import 'package:mesh_rescue/engine/models/envelope.dart';

class IdentityKeyPair {
  final SimpleKeyPair keyPair;
  final List<int> publicKeyBytes;
  final String publicKeyBase64;
  final String origin;

  const IdentityKeyPair({
    required this.keyPair,
    required this.publicKeyBytes,
    required this.publicKeyBase64,
    required this.origin,
  });
}

abstract interface class Signer {
  Future<IdentityKeyPair> generateKeyPair();
  Future<IdentityKeyPair> loadKeyPairFromSeed(List<int> seed);
  Future<String> signBytes(List<int> data, IdentityKeyPair identity);
  Future<bool> verifyBytes(
    List<int> data, {
    required String signatureBase64,
    required String publicKeyBase64,
  });
  Future<String> deriveOrigin(List<int> publicKeyBytes);
  Future<bool> matchesOrigin(String origin, String publicKeyBase64);
}

final class Ed25519Signer implements Signer {
  final Ed25519 _ed25519;
  final Sha256 _sha256;

  Ed25519Signer({Ed25519? ed25519, Sha256? sha256})
      : _ed25519 = ed25519 ?? Ed25519(),
        _sha256 = sha256 ?? Sha256();

  @override
  Future<IdentityKeyPair> generateKeyPair() async {
    final kp = await _ed25519.newKeyPair();
    final pub = await kp.extractPublicKey();
    final origin = await deriveOrigin(pub.bytes);
    return IdentityKeyPair(
      keyPair: kp,
      publicKeyBytes: List<int>.unmodifiable(pub.bytes),
      publicKeyBase64: base64Encode(pub.bytes),
      origin: origin,
    );
  }

  @override
  Future<IdentityKeyPair> loadKeyPairFromSeed(List<int> seed) async {
    if (seed.length != 32) {
      throw ArgumentError.value(seed.length, 'seed', 'Ed25519 seed must be 32 bytes');
    }
    final kp = await _ed25519.newKeyPairFromSeed(seed);
    final pub = await kp.extractPublicKey();
    final origin = await deriveOrigin(pub.bytes);
    return IdentityKeyPair(
      keyPair: kp,
      publicKeyBytes: List<int>.unmodifiable(pub.bytes),
      publicKeyBase64: base64Encode(pub.bytes),
      origin: origin,
    );
  }

  @override
  Future<String> signBytes(List<int> data, IdentityKeyPair identity) async {
    final sig = await _ed25519.sign(data, keyPair: identity.keyPair);
    return base64Encode(sig.bytes);
  }

  Future<Envelope> signEnvelope(
    Envelope unsigned,
    IdentityKeyPair identity,
  ) async {
    final bytes = canonicalJsonBytes(unsigned.signedMap());
    final sig = await signBytes(bytes, identity);
    return unsigned.copyWith(sig: sig);
  }

  @override
  Future<bool> verifyBytes(
    List<int> data, {
    required String signatureBase64,
    required String publicKeyBase64,
  }) async {
    final Uint8List pubBytes;
    final Uint8List sigBytes;
    try {
      pubBytes = base64Decode(publicKeyBase64);
      sigBytes = base64Decode(signatureBase64);
    } on FormatException {
      return false;
    }
    if (pubBytes.length != 32 || sigBytes.length != 64) {
      return false;
    }
    try {
      return await _ed25519.verify(
        data,
        signature: Signature(
          sigBytes,
          publicKey: SimplePublicKey(pubBytes, type: KeyPairType.ed25519),
        ),
      );
    } on ArgumentError {
      return false;
    }
  }

  Future<bool> verifyEnvelope(Envelope envelope) {
    final bytes = canonicalJsonBytes(envelope.signedMap());
    return verifyBytes(
      bytes,
      signatureBase64: envelope.sig,
      publicKeyBase64: envelope.originPub,
    );
  }

  @override
  Future<String> deriveOrigin(List<int> publicKeyBytes) async {
    if (publicKeyBytes.length != 32) {
      throw ArgumentError.value(
        publicKeyBytes.length,
        'publicKeyBytes',
        'Ed25519 public key must be 32 bytes',
      );
    }
    final digest = await _sha256.hash(publicKeyBytes);
    // First 4 bytes = 8 lowercase hex characters.
    final hex = StringBuffer();
    for (var i = 0; i < 4; i++) {
      hex.write(digest.bytes[i].toRadixString(16).padLeft(2, '0'));
    }
    return hex.toString();
  }

  @override
  Future<bool> matchesOrigin(String origin, String publicKeyBase64) async {
    final Uint8List pubBytes;
    try {
      pubBytes = base64Decode(publicKeyBase64);
    } on FormatException {
      return false;
    }
    if (pubBytes.length != 32) return false;
    final expected = await deriveOrigin(pubBytes);
    return origin == expected;
  }
}

