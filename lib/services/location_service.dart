import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:mesh_rescue/engine/clock.dart';

class GeoFix {
  final double lat;
  final double lng;
  final int timestampSeconds;
  final bool isStale;

  const GeoFix({
    required this.lat,
    required this.lng,
    required this.timestampSeconds,
    this.isStale = false,
  });

  GeoFix copyWith({bool? isStale}) => GeoFix(
        lat: lat,
        lng: lng,
        timestampSeconds: timestampSeconds,
        isStale: isStale ?? this.isStale,
      );
}

abstract interface class LocationProvider {
  Future<GeoFix?> getCurrentOrLastFix();
  Future<GeoFix?> getLastKnownFix();
}

/// Offline-safe GPS service using `geolocator` 14.x [LocationSettings] API.
/// Caches last known fix and marks it stale if a fresh fix fails.
class LocationService implements LocationProvider {
  static const int staleThresholdSeconds = 5 * 60;

  final Clock _clock;
  GeoFix? _cached;

  LocationService({Clock? clock}) : _clock = clock ?? const SystemClock();

  GeoFix? get cachedFix => _cached;

  @override
  Future<GeoFix?> getLastKnownFix() async {
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null) {
        final ts = pos.timestamp.millisecondsSinceEpoch ~/ 1000;
        final fix = GeoFix(
          lat: pos.latitude,
          lng: pos.longitude,
          timestampSeconds: ts,
          isStale: (_clock.nowSeconds() - ts) > staleThresholdSeconds,
        );
        _cached = fix;
        return fix;
      }
    } catch (_) {
      // Fallback to cached fix if platform location unavailable.
    }
    return _cached?.copyWith(isStale: true);
  }

  @override
  Future<GeoFix?> getCurrentOrLastFix() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        return await getLastKnownFix();
      }
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return await getLastKnownFix();
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 6),
        ),
      );
      final fix = GeoFix(
        lat: pos.latitude,
        lng: pos.longitude,
        timestampSeconds: _clock.nowSeconds(),
        isStale: false,
      );
      _cached = fix;
      return fix;
    } catch (_) {
      return await getLastKnownFix();
    }
  }
}

