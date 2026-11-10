import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesh_rescue/app/providers.dart';
import 'package:mesh_rescue/app/theme.dart';
import 'package:mesh_rescue/engine/models/enums.dart';
import 'package:mesh_rescue/ui/debug/debug_screen.dart';
import 'package:mesh_rescue/ui/debug/simulator_screen.dart';
import 'package:mesh_rescue/ui/hazard/report_hazard_sheet.dart';
import 'package:mesh_rescue/ui/responder/responder_screen.dart';
import 'package:mesh_rescue/ui/sos/sos_sheet.dart';
import 'package:mesh_rescue/ui/widgets/hold_sos_button.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  SosCategory _category = SosCategory.trapped;
  int _people = 1;

  @override
  Widget build(BuildContext context) {
    final mesh = ref.watch(meshControllerProvider);
    final controller = ref.read(meshControllerProvider.notifier);
    final activeSos = mesh.activeLocalSos();
    final fix = mesh.locationFix;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      mesh.peers.isEmpty
                          ? Icons.bluetooth_searching
                          : Icons.hub,
                      color: mesh.peers.isEmpty
                          ? MeshColors.hazardAmber
                          : MeshColors.verifiedGreen,
                      size: 26,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        mesh.peers.isEmpty
                            ? 'Searching for nearby phones…'
                            : '${mesh.peers.length} Phone(s) Connected',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Chip(label: Text('ID: ${mesh.deviceId ?? "—"}')),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Relayed: ${mesh.relayedCount} • Stored: ${mesh.messages.length} • '
                  'GPS: ${fix == null ? "unavailable" : "${fix.lat.toStringAsFixed(4)}, ${fix.lng.toStringAsFixed(4)}${fix.isStale ? " (stale)" : ""}"}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (activeSos != null)
          Card(
            color: activeSos.status == SosStatus.acknowledged
                ? const Color(0xFFE8F5E9)
                : const Color(0xFFFFEBEE),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        activeSos.status == SosStatus.acknowledged
                            ? Icons.check_circle
                            : Icons.sos,
                        color: activeSos.status == SosStatus.acknowledged
                            ? MeshColors.verifiedGreen
                            : MeshColors.sosRed,
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          activeSos.status == SosStatus.acknowledged
                              ? 'Help Acknowledged (${activeSos.ackStatus?.wireName ?? "RECEIVED"})'
                              : 'SOS ACTIVE — Rebroadcasting',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${activeSos.payload.category.wireName.toUpperCase()} • '
                    '${activeSos.payload.people} people'
                    '${activeSos.payload.note.isNotEmpty ? " • ${activeSos.payload.note}" : ""}',
                  ),
                  if (activeSos.latestAck != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Responder note: ${activeSos.latestAck!.envelope.parseAckPayload().note}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => controller.cancelLocalSos(activeSos.sos.id),
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text("I'm Safe (Cancel SOS)"),
                  ),
                ],
              ),
            ),
          )
        else ...[
          HoldSosButton(
            onTriggered: () async {
              await controller.sendSos(category: _category, people: _people);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('SOS broadcast started across mesh.'),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'SOS Preset & Details',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: SosCategory.values
                        .map(
                          (c) => ChoiceChip(
                            label: Text(c.wireName.toUpperCase()),
                            selected: _category == c,
                            onSelected: (_) => setState(() => _category = c),
                          ),
                        )
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('People: ',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      IconButton.outlined(
                        onPressed:
                            _people > 1 ? () => setState(() => _people--) : null,
                        icon: const Icon(Icons.remove),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text('$_people',
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w800)),
                      ),
                      IconButton.outlined(
                        onPressed: () => setState(() => _people++),
                        icon: const Icon(Icons.add),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () async {
                          final res = await showSosDetailsSheet(
                            context,
                            initialCategory: _category,
                            initialPeople: _people,
                            locationFix: fix,
                          );
                          if (res != null) {
                            await controller.sendSos(
                              category: res.category,
                              people: res.people,
                              note: res.note,
                              contact: res.contact,
                            );
                          }
                        },
                        icon: const Icon(Icons.edit_note),
                        label: const Text('Add Note'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: MeshColors.hazardAmber,
                ),
                onPressed: () => showReportHazardSheet(context),
                icon: const Icon(Icons.warning_amber_rounded),
                label: const Text('Report Hazard'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: mesh.isResponderUnlocked
                      ? MeshColors.verifiedGreen
                      : MeshColors.primaryBlue,
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ResponderScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.admin_panel_settings),
                label: Text(
                  mesh.isResponderUnlocked ? 'Responder (ON)' : 'Responder',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SimulatorScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.hub_outlined),
                label: const Text('20-Node Sim'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DebugScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.bug_report_outlined),
                label: const Text('Mesh Debug'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: SwitchListTile(
            title: const Text(
              'Battery Saver Mode',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'Longer discovery sleep window & 60s SOS rebroadcast',
            ),
            value: mesh.batterySaver,
            onChanged: (v) => controller.toggleBatterySaver(v),
          ),
        ),
      ],
    );
  }
}
