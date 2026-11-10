import 'dart:math' as math;

import 'package:mesh_rescue/data/message_store.dart';
import 'package:mesh_rescue/domain/geo.dart';
import 'package:mesh_rescue/engine/models/enums.dart';

class HazardCluster {
  final HazardKind kind;
  final String geohash;
  final double lat;
  final double lng;
  final int maxSeverity;
  final int distinctOriginsCount;
  final bool isConfirmed;
  final bool isResponderVerified;
  final int latestReceivedAt;
  final int minHops;
  final List<StoredMessage> reports;

  const HazardCluster({
    required this.kind,
    required this.geohash,
    required this.lat,
    required this.lng,
    required this.maxSeverity,
    required this.distinctOriginsCount,
    required this.isConfirmed,
    required this.isResponderVerified,
    required this.latestReceivedAt,
    required this.minHops,
    required this.reports,
  });

  String get confirmationLabel => isConfirmed ? 'CONFIRMED' : 'REPORTED';
}

/// Pure function clustering non-expired hazards by (kind, geohash-7).
/// Two or more distinct origins in the same cluster yield CONFIRMED status.
List<HazardCluster> clusterHazards(
  Iterable<StoredMessage> allHazards, {
  required int nowSeconds,
}) {
  final grouped = <({HazardKind kind, String geohash}), List<StoredMessage>>{};
  for (final msg in allHazards) {
    if (msg.type != MessageType.hazard) continue;
    final lat = msg.envelope.lat;
    final lng = msg.envelope.lng;
    if (lat == null || lng == null) continue;

    final payload = msg.envelope.parseHazardPayload();
    final geohash = msg.geohash ?? encodeGeohash7(lat, lng);
    final key = (kind: payload.kind, geohash: geohash);
    grouped.putIfAbsent(key, () => <StoredMessage>[]).add(msg);
  }

  final clusters = <HazardCluster>[];
  for (final entry in grouped.entries) {
    final reports = entry.value;
    final origins = reports.map((r) => r.envelope.origin).toSet();
    var maxSeverity = 1;
    var earliestRecv = reports.first.receivedAt;
    var latestRecv = 0;
    var minHops = 999;
    var responderVerified = false;
    var latestResponderRecv = 0;
    var latSum = 0.0;
    var lngSum = 0.0;

    for (final r in reports) {
      final p = r.envelope.parseHazardPayload();
      maxSeverity = math.max(maxSeverity, p.severity);
      earliestRecv = math.min(earliestRecv, r.receivedAt);
      latestRecv = math.max(latestRecv, r.receivedAt);
      minHops = math.min(minHops, r.envelope.hops);
      if (r.trust == TrustTier.verifiedResponder) {
        responderVerified = true;
        latestResponderRecv = math.max(latestResponderRecv, r.receivedAt);
      }
      latSum += r.envelope.lat!;
      lngSum += r.envelope.lng!;
    }

    final confirmationExtensions = math.max(0, origins.length - 1);
    final peerExpiresAt = earliestRecv +
        ExpiryDurations.hazardDefaultSeconds +
        confirmationExtensions * ExpiryDurations.hazardConfirmationBonusSeconds;
    final responderExpiresAt = responderVerified
        ? latestResponderRecv + ExpiryDurations.hazardResponderSeconds
        : 0;
    final clusterExpiresAt = math.max(
      math.max(peerExpiresAt, latestRecv + ExpiryDurations.hazardDefaultSeconds),
      responderExpiresAt,
    );

    if (nowSeconds >= clusterExpiresAt) continue;

    clusters.add(
      HazardCluster(
        kind: entry.key.kind,
        geohash: entry.key.geohash,
        lat: latSum / reports.length,
        lng: lngSum / reports.length,
        maxSeverity: maxSeverity,
        distinctOriginsCount: origins.length,
        isConfirmed: origins.length >= 2,
        isResponderVerified: responderVerified,
        latestReceivedAt: latestRecv,
        minHops: minHops,
        reports: List<StoredMessage>.unmodifiable(reports),
      ),
    );
  }

  clusters.sort((a, b) {
    if (a.isResponderVerified != b.isResponderVerified) {
      return a.isResponderVerified ? -1 : 1;
    }
    if (a.isConfirmed != b.isConfirmed) {
      return a.isConfirmed ? -1 : 1;
    }
    final sevCmp = b.maxSeverity.compareTo(a.maxSeverity);
    if (sevCmp != 0) return sevCmp;
    return b.latestReceivedAt.compareTo(a.latestReceivedAt);
  });
  return clusters;
}
