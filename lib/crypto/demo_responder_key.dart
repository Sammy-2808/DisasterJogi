import 'dart:convert';

import 'package:mesh_rescue/crypto/signer.dart';

/// DEMO ONLY: Hackathon responder signing key unlocked by a demo PIN.
/// Never use this key or PIN in production; replace assets/trusted_responders.json
/// and distribute responder keys out-of-band for real deployments.
abstract final class DemoResponderKey {
  static const String demoPin = '2026';
  static const String demoResponderName = 'District Control Room (DEMO)';
  static const String _demoSeedText = 'MESHR-DEMO-RESPONDER-KEY-2026-V1';

  static Future<IdentityKeyPair?> unlockWithPin(
    String pin, {
    Ed25519Signer? signer,
  }) async {
    if (pin != demoPin) return null;
    final seed = utf8.encode(_demoSeedText);
    return (signer ?? Ed25519Signer()).loadKeyPairFromSeed(seed);
  }
}

