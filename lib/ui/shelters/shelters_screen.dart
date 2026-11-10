import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesh_rescue/app/providers.dart';
import 'package:mesh_rescue/app/theme.dart';
import 'package:mesh_rescue/engine/models/enums.dart';
import 'package:mesh_rescue/ui/responder/responder_screen.dart';
import 'package:mesh_rescue/ui/widgets/trust_badge.dart';

class SheltersScreen extends ConsumerWidget {
  const SheltersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mesh = ref.watch(meshControllerProvider);
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // Strictly verified responder shelters only
    final shelters = mesh.shelters(
      includeUnverified: false,
      nowSeconds: nowSec,
    );
    final verified = shelters.where((s) => s.isVerified).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Responder Action Banner
        if (mesh.isResponderUnlocked)
          Card(
            color: const Color(0xFFE8F5E9),
            child: ListTile(
              leading: const Icon(Icons.add_location_alt,
                  color: MeshColors.verifiedGreen),
              title: const Text(
                'Responder Mode Active',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('Add or update verified shelter locations.'),
              trailing: FilledButton.tonal(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ResponderScreen(),
                    ),
                  );
                },
                child: const Text('Add Shelter'),
              ),
            ),
          )
        else
          Card(
            child: ListTile(
              leading: const Icon(Icons.security, color: MeshColors.primaryBlue),
              title: const Text('Responder Authority Mode'),
              subtitle: const Text('Unlock to publish signed shelter locations.'),
              trailing: TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ResponderScreen(),
                    ),
                  );
                },
                child: const Text('Unlock'),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Verified Responder Shelters (${verified.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_user, color: MeshColors.verifiedGreen, size: 16),
                SizedBox(width: 4),
                Text(
                  'Responder Verified Only',
                  style: TextStyle(
                    color: MeshColors.verifiedGreen,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (verified.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Icon(Icons.shield_outlined,
                      size: 48, color: MeshColors.verifiedGreen),
                  const SizedBox(height: 12),
                  Text(
                    'No Responder-Verified Shelters Yet',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Shelters appear here and on the Radar map only when marked and cryptographically signed by authorized emergency responders.\n\n'
                    'If no responders or peers are nearby, as soon as another device connects to your mesh, shelter locations will automatically sync and display.',
                    textAlign: TextAlign.center,
                  ),
                ],
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
                    if (item.message.envelope.lat != null &&
                        item.message.envelope.lng != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.place_outlined,
                              size: 16, color: MeshColors.inkSecondary),
                          const SizedBox(width: 4),
                          Text(
                            'Location: ${item.message.envelope.lat!.toStringAsFixed(5)}, ${item.message.envelope.lng!.toStringAsFixed(5)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
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
      ],
    );
  }
}
