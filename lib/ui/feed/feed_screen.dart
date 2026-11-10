import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesh_rescue/app/providers.dart';
import 'package:mesh_rescue/app/theme.dart';
import 'package:mesh_rescue/engine/models/enums.dart';
import 'package:mesh_rescue/ui/widgets/trust_badge.dart';

class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mesh = ref.watch(meshControllerProvider);
    final controller = ref.read(meshControllerProvider.notifier);
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final sosList = mesh.sosAlerts(nowSeconds: nowSec);
    final hazards = mesh.hazardClusters(nowSeconds: nowSec);
    final shelters = mesh.shelters(nowSeconds: nowSec);

    if (sosList.isEmpty && hazards.isEmpty && shelters.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.list_alt, size: 56, color: MeshColors.inkSecondary),
              SizedBox(height: 12),
              Text(
                'No Mesh Alerts Yet',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 8),
              Text(
                'SOS alerts, hazard reports, and verified shelters received from nearby phones will appear here sorted by priority.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (sosList.isNotEmpty) ...[
          Text('SOS Alerts (${sosList.length})',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final item in sosList) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.sos, color: MeshColors.sosRed),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${item.payload.category.wireName.toUpperCase()} • ${item.payload.people} people',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Chip(label: Text(item.status.wireName)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TrustBadge(
                      tier: item.sos.trust,
                      responderName: mesh.trustService
                          .responderNameForPub(item.sos.envelope.originPub),
                    ),
                    const SizedBox(height: 8),
                    if (item.payload.note.isNotEmpty) Text(item.payload.note),
                    const SizedBox(height: 6),
                    Text(
                      '${formatHopsLabel(item.sos.envelope.hops)} • ${formatAge(item.sos.receivedAt, nowSec)}'
                      '${_formatDist(mesh.distanceMetersTo(item.sos.envelope.lat, item.sos.envelope.lng))}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (item.sos.isLocal &&
                        (item.status == SosStatus.active ||
                            item.status == SosStatus.acknowledged)) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => controller.cancelLocalSos(item.sos.id),
                        icon: const Icon(Icons.check),
                        label: const Text("I'm Safe (Cancel SOS)"),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
        ],
        if (hazards.isNotEmpty) ...[
          Text('Hazards (${hazards.length})',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final cluster in hazards) ...[
            Builder(
              builder: (context) {
                final primary = cluster.reports.first;
                final alreadyReported = cluster.reports
                    .any((r) => r.envelope.origin == mesh.deviceId);
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: MeshColors.hazardAmber),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${cluster.kind.wireName.replaceAll('_', ' ').toUpperCase()} • Sev ${cluster.maxSeverity}/5',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Chip(
                              label: Text(
                                '${cluster.confirmationLabel} (${cluster.distinctOriginsCount})',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        TrustBadge(
                          tier: cluster.isResponderVerified
                              ? TrustTier.verifiedResponder
                              : primary.trust,
                        ),
                        const SizedBox(height: 8),
                        if (primary.envelope.parseHazardPayload().note.isNotEmpty)
                          Text(primary.envelope.parseHazardPayload().note),
                        const SizedBox(height: 6),
                        Text(
                          '${formatHopsLabel(cluster.minHops)} • ${formatAge(cluster.latestReceivedAt, nowSec)}'
                          '${_formatDist(mesh.distanceMetersTo(cluster.lat, cluster.lng))}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (!alreadyReported) ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: () async {
                              await controller.reportHazard(
                                kind: cluster.kind,
                                severity: cluster.maxSeverity,
                                note: 'Confirmed hazard nearby',
                                confirmRefId: primary.id,
                                fallbackLat: cluster.lat,
                                fallbackLng: cluster.lng,
                              );
                            },
                            icon: const Icon(Icons.thumb_up_alt_outlined),
                            label: const Text('Confirm Hazard'),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
        ],
        if (shelters.isNotEmpty) ...[
          Text('Verified Shelters (${shelters.length})',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final sh in shelters) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.shield, color: MeshColors.verifiedGreen),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            sh.payload.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Chip(label: Text(sh.payload.status.wireName)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TrustBadge(
                      tier: sh.message.trust,
                      responderName: mesh.trustService
                          .responderNameForPub(sh.message.envelope.originPub),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Verified safe • Capacity ${sh.payload.capacity} • '
                      '${formatHopsLabel(sh.message.envelope.hops)}'
                      '${_formatDist(sh.distanceMeters)}',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  String _formatDist(double? meters) {
    if (meters == null) return '';
    if (meters < 1000) return ' • ${meters.round()} m';
    return ' • ${(meters / 1000).toStringAsFixed(1)} km';
  }
}
