import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mesh_rescue/crypto/signer.dart';

/// Persists the device's Ed25519 32-byte seed in Android KeyStore-backed
/// [FlutterSecureStorage]. Never logs the seed and never writes it to SQLite.
class DeviceIdentityStore {
  static const String _seedKey = 'meshrescue_device_seed_v1';

  final FlutterSecureStorage _storage;
  final Ed25519Signer _signer;

  DeviceIdentityStore({
    FlutterSecureStorage? storage,
    Ed25519Signer? signer,
  })  : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
            ),
        _signer = signer ?? Ed25519Signer();

  Future<IdentityKeyPair> loadOrCreate() async {
    final existing = await _storage.read(key: _seedKey);
    if (existing != null && existing.isNotEmpty) {
      List<int>? seed;
      try {
        seed = base64Decode(existing);
      } on FormatException {
        seed = null;
      }
      if (seed != null && seed.length == 32) {
        return _signer.loadKeyPairFromSeed(seed);
      }
    }

    final rng = Random.secure();
    final seed = List<int>.generate(32, (_) => rng.nextInt(256));
    await _storage.write(key: _seedKey, value: base64Encode(seed));
    return _signer.loadKeyPairFromSeed(seed);
  }
}
