import 'dart:convert';

import 'package:mesh_rescue/engine/models/enums.dart';

class TrustedResponder {
  final String name;
  final String pub;

  const TrustedResponder({
    required this.name,
    required this.pub,
  });

  factory TrustedResponder.fromJson(Map<String, Object?> json) {
    final name = json['name'];
    final pub = json['pub'];
    if (name is! String || name.isEmpty || pub is! String || pub.isEmpty) {
      throw const FormatException('Invalid trusted responder entry');
    }
    return TrustedResponder(name: name, pub: pub);
  }
}

/// Pure-Dart trust resolver backed by parsed `assets/trusted_responders.json`.
class TrustService {
  final Map<String, TrustedResponder> _byPub;

  TrustService(Iterable<TrustedResponder> responders)
      : _byPub = {for (final r in responders) r.pub: r};

  factory TrustService.empty() => TrustService(const []);

  factory TrustService.fromJsonString(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('trusted_responders.json must be an object');
    }
    final version = decoded['version'];
    if (version != 1) {
      throw FormatException('Unsupported trusted_responders version: $version');
    }
    final respondersRaw = decoded['responders'];
    if (respondersRaw is! List) {
      throw const FormatException('responders must be a JSON array');
    }
    final list = respondersRaw
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => TrustedResponder.fromJson(Map<String, Object?>.from(e)))
        .toList(growable: false);
    return TrustService(list);
  }

  bool isTrustedResponderPub(String originPub) => _byPub.containsKey(originPub);

  String? responderNameForPub(String originPub) => _byPub[originPub]?.name;

  List<TrustedResponder> get responders =>
      List<TrustedResponder>.unmodifiable(_byPub.values);

  TrustTier evaluateTrust({
    required MessageType type,
    required String originPub,
    required bool signatureValid,
  }) {
    if (!signatureValid) {
      return TrustTier.unverified;
    }
    if (isTrustedResponderPub(originPub)) {
      return TrustTier.verifiedResponder;
    }
    // Shelters from non-responder keys are always downgraded to UNVERIFIED.
    if (type == MessageType.shelter) {
      return TrustTier.unverified;
    }
    return TrustTier.signedPeer;
  }
}

