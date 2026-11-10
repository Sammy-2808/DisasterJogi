import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesh_rescue/app/providers.dart';
import 'package:mesh_rescue/app/theme.dart';
import 'package:mesh_rescue/engine/models/enums.dart';

class DebugScreen extends ConsumerWidget {
  const DebugScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mesh = ref.watch(meshControllerProvider);
    final controller = ref.read(meshControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Mesh Debug')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Node Identity: ${mesh.deviceId ?? "—"}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _StatusBadge(
                        label: mesh.isAdvertising
                            ? 'Advertising ON'
                            : 'Advertising OFF',
                        ok: mesh.isAdvertising,
                      ),
                      _StatusBadge(
                        label: mesh.isDiscovering
                            ? 'Discovering ON'
                            : 'Discovering OFF',
                        ok: mesh.isDiscovering,
                      ),
                      _StatusBadge(
                        label: 'Peers: ${mesh.peers.length}',
                        ok: mesh.peers.isNotEmpty,
                      ),
                      _StatusBadge(
                        label: 'Relayed: ${mesh.relayedCount}',
                        ok: mesh.relayedCount > 0,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => controller.sendTestMessage(),
                          icon: const Icon(Icons.send),
                          label: const Text('Send Test Msg'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () => controller.restartRadio(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Restart'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Connected Peers (${mesh.peers.length})',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          if (mesh.peers.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No peers connected yet. Searching…'),
              ),
            )
          else
            ...mesh.peers.map(
              (p) => Card(
                child: ListTile(
                  leading: Icon(
                    p.state == 'CONNECTED'
                        ? Icons.link
                        : Icons.sync,
                    color: p.state == 'CONNECTED'
                        ? MeshColors.verifiedGreen
                        : MeshColors.hazardAmber,
                  ),
                  title: Text('Peer ${p.peerId} (${p.state})'),
                  subtitle: Text(
                    'Endpoint: ${p.endpointId} | Last frame: ${p.lastFrameAtSec ?? "none"}',
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text('Stored Messages (${mesh.messages.length})',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          if (mesh.messages.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No messages stored yet.'),
              ),
            )
          else
            ...mesh.messages.take(20).map(
                  (m) => Card(
                    child: ListTile(
                      title: Text(
                        '${m.type.wireName} • from ${m.envelope.origin} '
                        '• hops=${m.envelope.hops} ttl=${m.envelope.ttl}',
                      ),
                      subtitle: Text(
                        'id=${m.id.substring(0, 8)} trust=${m.trust.wireName}\n'
                        'payload=${m.envelope.payload}',
                      ),
                    ),
                  ),
                ),
          const SizedBox(height: 12),
          Text('Drop Counts by Reason',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                children: DropReason.values
                    .map(
                      (r) => Chip(
                        label: Text('${r.code}: ${mesh.dropCounts[r] ?? 0}'),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Transport Logs ([MESH])',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                mesh.logs.isEmpty
                    ? 'No logs yet.'
                    : mesh.logs.reversed.join('\n'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final bool ok;

  const _StatusBadge({required this.label, required this.ok});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ok ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: ok ? MeshColors.verifiedGreen : MeshColors.hazardAmber,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.info_outline,
            size: 16,
            color: ok ? MeshColors.verifiedGreen : MeshColors.hazardAmber,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: ok ? MeshColors.verifiedGreen : MeshColors.hazardAmber,
            ),
          ),
        ],
      ),
    );
  }
}

