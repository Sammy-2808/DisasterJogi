import 'package:mesh_rescue/data/message_store.dart';
import 'package:mesh_rescue/domain/geo.dart';
import 'package:mesh_rescue/engine/models/enums.dart';
import 'package:mesh_rescue/engine/models/payloads.dart';

class ResolvedShelter {
  final StoredMessage message;
  final ShelterPayload payload;
  final bool isVerified;
  final double? distanceMeters;

  const ResolvedShelter({
    required this.message,
    required this.payload,
    required this.isVerified,
    this.distanceMeters,
  });

  String get origin => message.envelope.origin;
  String get key => payload.key;
  int get seq => payload.seq;
}

/// Pure function resolving effective shelters by `(origin, key)` using highest
/// `seq`, filtering expired/CLOSED listings, and sorting Verified Responder
/// listings first.
List<ResolvedShelter> resolveShelters(
  Iterable<StoredMessage> allMessages, {
  required int nowSeconds,
  bool includeUnverified = false,
  bool includeClosed = false,
  double? userLat,
  double? userLng,
}) {
  final latestByKey = <({String origin, String key}), StoredMessage>{};

  for (final msg in allMessages) {
    if (msg.type != MessageType.shelter) continue;
    final payload = msg.envelope.parseShelterPayload();
    final composite = (origin: msg.envelope.origin, key: payload.key);
    final existing = latestByKey[composite];
    if (existing == null) {
      latestByKey[composite] = msg;
      continue;
    }
    final existingPayload = existing.envelope.parseShelterPayload();
    if (payload.seq > existingPayload.seq ||
        (payload.seq == existingPayload.seq &&
            msg.receivedAt > existing.receivedAt)) {
      latestByKey[composite] = msg;
    }
  }

  final out = <ResolvedShelter>[];
  for (final msg in latestByKey.values) {
    if (nowSeconds - msg.receivedAt >= ExpiryDurations.shelterSeconds) {
      continue;
    }
    final payload = msg.envelope.parseShelterPayload();
    if (!includeClosed && payload.status == ShelterStatus.closed) {
      continue;
    }
    final isVerified = msg.trust == TrustTier.verifiedResponder;
    if (!includeUnverified && !isVerified) {
      continue;
    }
    double? dist;
    if (userLat != null &&
        userLng != null &&
        msg.envelope.lat != null &&
        msg.envelope.lng != null) {
      dist = haversineDistanceMeters(
        userLat,
        userLng,
        msg.envelope.lat!,
        msg.envelope.lng!,
      );
    }
    out.add(
      ResolvedShelter(
        message: msg,
        payload: payload,
        isVerified: isVerified,
        distanceMeters: dist,
      ),
    );
  }

  out.sort((a, b) {
    if (a.isVerified != b.isVerified) {
      return a.isVerified ? -1 : 1;
    }
    if (a.distanceMeters != null && b.distanceMeters != null) {
      return a.distanceMeters!.compareTo(b.distanceMeters!);
    }
    return b.message.receivedAt.compareTo(a.message.receivedAt);
  });
  return out;
}

