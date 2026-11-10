import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesh_rescue/app/providers.dart';
import 'package:mesh_rescue/app/theme.dart';
import 'package:mesh_rescue/domain/geo.dart';
import 'package:mesh_rescue/engine/models/enums.dart';
import 'package:mesh_rescue/services/mesh_controller.dart';
import 'package:mesh_rescue/ui/radar/radar_view.dart';
import 'package:mesh_rescue/ui/widgets/trust_badge.dart';

class MapScreen extends ConsumerWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mesh = ref.watch(meshControllerProvider);
    final fix = mesh.locationFix;
    final refLat = fix?.lat ?? 21.4669;
    final refLng = fix?.lng ?? 83.9812;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final sosList = mesh.sosAlerts(nowSeconds: nowSec);
    final hazards = mesh.hazardClusters(nowSeconds: nowSec);
    // Only verified responder shelters are included
    final shelters = mesh.shelters(includeUnverified: false, nowSeconds: nowSec);

    final blips = <RadarBlip>[];

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
    }

    // Shelters: Strictly show verified shelters marked by responders
    for (final sh in shelters) {
      if (!sh.isVerified) continue;
      final lat = sh.message.envelope.lat;
      final lng = sh.message.envelope.lng;
      if (lat == null || lng == null) continue;
      blips.add(
        RadarBlip(
          id: sh.message.id,
          label: 'Shelter: ${sh.payload.name}',
          type: MessageType.shelter,
          trust: TrustTier.verifiedResponder,
          distanceMeters: haversineDistanceMeters(refLat, refLng, lat, lng),
          bearingDegrees: initialBearingDegrees(refLat, refLng, lat, lng),
          detail: '${sh.payload.status.wireName} • Verified safe (Responder)',
        ),
      );
    }

    blips.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

    return RadarView(
      blips: blips,
      hasUserLocation: fix != null,
      onTapBlip: (blip) => _showBlipDetails(context, blip, mesh),
    );
  }

  void _showBlipDetails(BuildContext context, RadarBlip blip, MeshUiState mesh) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final distStr = blip.distanceMeters < 1000
            ? '${blip.distanceMeters.round()} m'
            : '${(blip.distanceMeters / 1000).toStringAsFixed(1)} km';

        // Check if this is a shelter
        final shelterMatch = mesh.shelters().where((s) => s.message.id == blip.id).firstOrNull;

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    blip.type == MessageType.shelter
                        ? Icons.shield
                        : blip.type == MessageType.sos
                            ? Icons.sos
                            : Icons.warning_amber_rounded,
                    color: blip.type == MessageType.shelter
                        ? MeshColors.verifiedGreen
                        : blip.type == MessageType.sos
                            ? MeshColors.sosRed
                            : MeshColors.hazardAmber,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      blip.label,
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (blip.type == MessageType.shelter) ...[
                const TrustBadge(
                  tier: TrustTier.verifiedResponder,
                  responderName: 'Authorized Responder',
                ),
                const SizedBox(height: 10),
                const Text(
                  'Verified safe shelter listing marked by emergency responders.',
                  style: TextStyle(
                    color: MeshColors.verifiedGreen,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (shelterMatch != null) ...[
                  const SizedBox(height: 8),
                  Text('Capacity: ${shelterMatch.payload.capacity}'),
                  Text('Status: ${shelterMatch.payload.status.wireName}'),
                  if (shelterMatch.payload.services.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: shelterMatch.payload.services
                          .map((s) => Chip(label: Text(s)))
                          .toList(growable: false),
                    ),
                  ],
                  if (shelterMatch.payload.note.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('Note: ${shelterMatch.payload.note}'),
                  ],
                  if (shelterMatch.message.envelope.lat != null &&
                      shelterMatch.message.envelope.lng != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Coordinates: ${shelterMatch.message.envelope.lat!.toStringAsFixed(5)}, ${shelterMatch.message.envelope.lng!.toStringAsFixed(5)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ],
              const SizedBox(height: 10),
              Text(
                'Distance: $distStr • Bearing: ${blip.bearingDegrees.round()}°',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
