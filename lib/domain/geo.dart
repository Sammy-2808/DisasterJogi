import 'dart:math' as math;

import 'package:dart_geohash/dart_geohash.dart';

const double _earthRadiusMeters = 6371000.0;
final GeoHasher _geoHasher = GeoHasher();

/// Encodes (lat, lng) into a precision-7 geohash (~150 m cell).
/// Note: dart_geohash expects (longitude, latitude) parameter order.
String encodeGeohash7(double lat, double lng) {
  return _geoHasher.encode(lng, lat, precision: 7);
}

/// Great-circle distance in meters using the Haversine formula.
double haversineDistanceMeters(
  double lat1,
  double lng1,
  double lat2,
  double lng2,
) {
  final dLat = _toRadians(lat2 - lat1);
  final dLng = _toRadians(lng2 - lng1);
  final rLat1 = _toRadians(lat1);
  final rLat2 = _toRadians(lat2);

  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rLat1) *
          math.cos(rLat2) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return _earthRadiusMeters * c;
}

/// Initial great-circle bearing in degrees [0, 360) from point 1 to point 2.
double initialBearingDegrees(
  double lat1,
  double lng1,
  double lat2,
  double lng2,
) {
  final rLat1 = _toRadians(lat1);
  final rLat2 = _toRadians(lat2);
  final dLng = _toRadians(lng2 - lng1);

  final y = math.sin(dLng) * math.cos(rLat2);
  final x = math.cos(rLat1) * math.sin(rLat2) -
      math.sin(rLat1) * math.cos(rLat2) * math.cos(dLng);
  final theta = math.atan2(y, x);
  return (_toDegrees(theta) + 360.0) % 360.0;
}

double _toRadians(double deg) => deg * (math.pi / 180.0);
double _toDegrees(double rad) => rad * (180.0 / math.pi);

