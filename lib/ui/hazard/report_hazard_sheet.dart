import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesh_rescue/app/providers.dart';
import 'package:mesh_rescue/app/theme.dart';
import 'package:mesh_rescue/engine/models/enums.dart';

Future<void> showReportHazardSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _ReportHazardSheet(),
  );
}

class _ReportHazardSheet extends ConsumerStatefulWidget {
  const _ReportHazardSheet();

  @override
  ConsumerState<_ReportHazardSheet> createState() => _ReportHazardSheetState();
}

class _ReportHazardSheetState extends ConsumerState<_ReportHazardSheet> {
  HazardKind _kind = HazardKind.flood;
  int _severity = 3;
  final TextEditingController _noteController = TextEditingController();
  bool _useFallbackCoordsIfNoGps = true;
  bool _submitting = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mesh = ref.watch(meshControllerProvider);
    final controller = ref.read(meshControllerProvider.notifier);
    final fix = mesh.locationFix;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: MeshColors.hazardAmber, size: 28),
                const SizedBox(width: 8),
                Text(
                  'Report Hazard',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: HazardKind.values
                  .map(
                    (k) => ChoiceChip(
                      label: Text(k.wireName.replaceAll('_', ' ').toUpperCase()),
                      selected: _kind == k,
                      onSelected: (_) => setState(() => _kind = k),
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 16),
            Text('Severity: $_severity / 5',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Slider(
              value: _severity.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              label: '$_severity',
              onChanged: (v) => setState(() => _severity = v.round()),
            ),
            TextField(
              controller: _noteController,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Hazard details (optional)',
                hintText: 'e.g. Water waist-deep, bridge blocked',
                border: OutlineInputBorder(),
              ),
            ),
            if (fix == null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use demo area pin if GPS unavailable indoors'),
                value: _useFallbackCoordsIfNoGps,
                onChanged: (v) => setState(() => _useFallbackCoordsIfNoGps = v),
              )
            else
              Text(
                'Location: ${fix.lat.toStringAsFixed(5)}, ${fix.lng.toStringAsFixed(5)}'
                '${fix.isStale ? " (stale cached GPS)" : ""}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: MeshColors.hazardAmber,
              ),
              onPressed: _submitting
                  ? null
                  : () async {
                      setState(() => _submitting = true);
                      final ok = await controller.reportHazard(
                        kind: _kind,
                        severity: _severity,
                        note: _noteController.text,
                        fallbackLat: _useFallbackCoordsIfNoGps ? 21.4669 : null,
                        fallbackLng: _useFallbackCoordsIfNoGps ? 83.9812 : null,
                      );
                      if (!context.mounted) return;
                      setState(() => _submitting = false);
                      if (ok) {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Hazard signed and queued for mesh relay.'),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Waiting for GPS fix—enable fallback or step outside.'),
                          ),
                        );
                      }
                    },
              icon: const Icon(Icons.campaign),
              label: const Text('Broadcast Hazard Report'),
            ),
          ],
        ),
      ),
    );
  }
}

