import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesh_rescue/app/providers.dart';
import 'package:mesh_rescue/app/theme.dart';
import 'package:mesh_rescue/engine/models/enums.dart';
import 'package:mesh_rescue/ui/widgets/trust_badge.dart';

class SheltersScreen extends ConsumerStatefulWidget {
  const SheltersScreen({super.key});

  @override
  ConsumerState<SheltersScreen> createState() => _SheltersScreenState();
}

class _SheltersScreenState extends ConsumerState<SheltersScreen> {
  bool _showUnverified = false;

  @override
  Widget build(BuildContext context) {
    final mesh = ref.watch(meshControllerProvider);
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final shelters = mesh.shelters(
      includeUnverified: _showUnverified,
      nowSeconds: nowSec,
    );
    final verified = shelters.where((s) => s.isVerified).toList();
    final unverified = shelters.where((s) => !s.isVerified).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: SwitchListTile(
            title: const Text(
              'Show community-reported (Unverified)',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'Unverified entries are NOT responder-signed and may be inaccurate or forged.',
            ),
            value: _showUnverified,
            onChanged: (v) => setState(() => _showUnverified = v),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Verified Responder Shelters (${verified.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (verified.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No responder-verified shelters received yet. Shelters appear here only when signed by a trusted responder key.',
              ),
            ),
          )
        else
          for (final item in verified) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.verified_user,
                            color: MeshColors.verifiedGreen, size: 28),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.payload.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Chip(
                          label: Text(item.payload.status.wireName),
                          backgroundColor: item.payload.status == ShelterStatus.open
                              ? const Color(0xFFE8F5E9)
                              : const Color(0xFFFFF3E0),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TrustBadge(
                      tier: TrustTier.verifiedResponder,
                      responderName: mesh.trustService
                          .responderNameForPub(item.message.envelope.originPub),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Verified safe shelter listing',
                      style: TextStyle(
                        color: MeshColors.verifiedGreen,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Capacity: ${item.payload.capacity} • Update #${item.seq}'
                      '${item.distanceMeters != null ? " • ${item.distanceMeters! < 1000 ? "${item.distanceMeters!.round()} m" : "${(item.distanceMeters! / 1000).toStringAsFixed(1)} km"}" : ""}',
                    ),
                    if (item.payload.services.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        children: item.payload.services
                            .map((s) => Chip(label: Text(s)))
                            .toList(growable: false),
                      ),
                    ],
                    if (item.payload.note.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('Note: ${item.payload.note}'),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      '${formatHopsLabel(item.message.envelope.hops)} • ${formatAge(item.message.receivedAt, nowSec)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        if (_showUnverified && unverified.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: MeshColors.hazardAmber, width: 1.5),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: MeshColors.hazardAmber),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'UNVERIFIED REPORTS: Not signed by any trusted authority. Exercise extreme caution.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final item in unverified) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
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
                            item.payload.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Chip(label: Text(item.payload.status.wireName)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const TrustBadge(tier: TrustTier.unverified),
                    const SizedBox(height: 6),
                    Text('Unverified community report • Capacity ${item.payload.capacity}'),
                    if (item.payload.note.isNotEmpty) Text(item.payload.note),
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
}
