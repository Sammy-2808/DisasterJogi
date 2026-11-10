import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:mesh_rescue/app/providers.dart';
import 'package:mesh_rescue/app/theme.dart';
import 'package:mesh_rescue/domain/geo.dart';
import 'package:mesh_rescue/engine/models/enums.dart';
import 'package:mesh_rescue/ui/radar/radar_view.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  bool _showVectorMap = false;

  @override
  Widget build(BuildContext context) {
    final mesh = ref.watch(meshControllerProvider);
    final fix = mesh.locationFix;
    final refLat = fix?.lat ?? 21.4669;
    final refLng = fix?.lng ?? 83.9812;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final sosList = mesh.sosAlerts(nowSeconds: nowSec);
    final hazards = mesh.hazardClusters(nowSeconds: nowSec);
    final shelters = mesh.shelters(nowSeconds: nowSec);

    final blips = <RadarBlip>[];
    final markers = <Marker>[
      if (fix != null)
        Marker(
          point: LatLng(fix.lat, fix.lng),
          width: 40,
          height: 40,
          child: const Icon(Icons.my_location, color: MeshColors.primaryBlue, size: 30),
        ),
    ];

    for (final s in sosList) {
      final lat = s.sos.envelope.lat;
      final lng = s.sos.envelope.lng;
      if (lat == null || lng == null) continue;
      blips.add(
        RadarBlip(
          id: s.sos.id,
          label: 'SOS: ${s.payload.category.wireName.toUpperCase()} (${s.payload.people})',
          type: MessageType.sos,
          trust: s.sos.trust,
          distanceMeters: haversineDistanceMeters(refLat, refLng, lat, lng),
          bearingDegrees: initialBearingDegrees(refLat, refLng, lat, lng),
          detail: s.status.wireName,
        ),
      );
      markers.add(
        Marker(
          point: LatLng(lat, lng),
          width: 44,
          height: 44,
          child: const Icon(Icons.sos, color: MeshColors.sosRed, size: 32),
        ),
      );
    }

    for (final h in hazards) {
      blips.add(
        RadarBlip(
          id: h.reports.first.id,
          label: 'Hazard: ${h.kind.wireName.replaceAll('_', ' ')} (Sev ${h.maxSeverity})',
          type: MessageType.hazard,
          trust: h.isResponderVerified
              ? TrustTier.verifiedResponder
              : TrustTier.signedPeer,
          distanceMeters: haversineDistanceMeters(refLat, refLng, h.lat, h.lng),
          bearingDegrees: initialBearingDegrees(refLat, refLng, h.lat, h.lng),
          detail: h.confirmationLabel,
        ),
      );
      markers.add(
        Marker(
          point: LatLng(h.lat, h.lng),
          width: 40,
          height: 40,
          child: const Icon(Icons.warning_amber_rounded,
              color: MeshColors.hazardAmber, size: 30),
        ),
      );
    }

    for (final sh in shelters) {
      final lat = sh.message.envelope.lat;
      final lng = sh.message.envelope.lng;
      if (lat == null || lng == null) continue;
      blips.add(
        RadarBlip(
          id: sh.message.id,
          label: 'Shelter: ${sh.payload.name}',
          type: MessageType.shelter,
          trust: sh.message.trust,
          distanceMeters: haversineDistanceMeters(refLat, refLng, lat, lng),
          bearingDegrees: initialBearingDegrees(refLat, refLng, lat, lng),
          detail: '${sh.payload.status.wireName} • Verified safe',
        ),
      );
      markers.add(
        Marker(
          point: LatLng(lat, lng),
          width: 40,
          height: 40,
          child: const Icon(Icons.shield, color: MeshColors.verifiedGreen, size: 30),
        ),
      );
    }

    blips.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.radar),
                label: Text('Radar (No Tiles)'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.map_outlined),
                label: Text('Offline Pin Canvas'),
              ),
            ],
            selected: {_showVectorMap},
            onSelectionChanged: (sel) =>
                setState(() => _showVectorMap = sel.first),
          ),
        ),
        Expanded(
          child: _showVectorMap
              ? Stack(
                  children: [
                    FlutterMap(
                      options: MapOptions(
                        initialCenter: LatLng(refLat, refLng),
                        initialZoom: 15,
                        backgroundColor: const Color(0xFFE8EEF2),
                      ),
                      children: [
                        MarkerLayer(markers: markers),
                      ],
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            'Offline pin canvas (no raster tiles bundled). '
                            'Center: ${refLat.toStringAsFixed(4)}, ${refLng.toStringAsFixed(4)} • '
                            '${markers.length} marker(s).',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : RadarView(
                  blips: blips,
                  hasUserLocation: fix != null,
                ),
        ),
      ],
    );
  }
}
