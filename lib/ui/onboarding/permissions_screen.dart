import 'package:flutter/material.dart';
import 'package:mesh_rescue/app/theme.dart';
import 'package:mesh_rescue/services/permission_service.dart';

class PermissionsScreen extends StatelessWidget {
  final MeshPermissionsState? permissionsState;
  final VoidCallback onRequestPermissions;
  final VoidCallback onOpenLocationSettings;
  final VoidCallback onOpenAppSettings;
  final VoidCallback onRecheck;

  const PermissionsScreen({
    super.key,
    required this.permissionsState,
    required this.onRequestPermissions,
    required this.onOpenLocationSettings,
    required this.onOpenAppSettings,
    required this.onRecheck,
  });

  @override
  Widget build(BuildContext context) {
    final granted = permissionsState?.allPermissionsGranted ?? false;
    final locOn = permissionsState?.locationServiceEnabled ?? false;
    final permDenied = permissionsState?.permanentlyDenied ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('MeshRescue Setup')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(
              Icons.bluetooth_searching,
              size: 64,
              color: MeshColors.primaryBlue,
            ),
            const SizedBox(height: 16),
            Text(
              'Offline Mesh Permissions',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'MeshRescue works with zero internet or cell service. Android requires these permissions to discover nearby phones and attach GPS coordinates to SOS alerts.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            _ReasonCard(
              icon: Icons.bluetooth,
              title: 'Bluetooth & Nearby Wi-Fi',
              subtitle:
                  'Lets your phone discover nearby devices and relay SOS, hazards, and shelters hop-by-hop.',
              ok: granted,
            ),
            const SizedBox(height: 12),
            _ReasonCard(
              icon: Icons.location_on,
              title: 'Precise Location & Location Toggle',
              subtitle:
                  'Required by Android Nearby discovery and for attaching offline satellite GPS coordinates to alerts.',
              ok: granted && locOn,
            ),
            const SizedBox(height: 24),
            if (!granted) ...[
              FilledButton.icon(
                onPressed: permDenied ? onOpenAppSettings : onRequestPermissions,
                icon: Icon(permDenied ? Icons.settings : Icons.check_circle),
                label: Text(
                  permDenied
                      ? 'Open App Settings to Grant'
                      : 'Grant Mesh Permissions',
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (!locOn) ...[
              FilledButton.tonalIcon(
                onPressed: onOpenLocationSettings,
                icon: const Icon(Icons.gps_fixed),
                label: const Text('Turn On Device Location'),
              ),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              onPressed: onRecheck,
              icon: const Icon(Icons.refresh),
              label: const Text('Re-check Status'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasonCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool ok;

  const _ReasonCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.ok,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 32,
              color: ok ? MeshColors.verifiedGreen : MeshColors.primaryBlue,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Icon(
                        ok ? Icons.check_circle : Icons.pending,
                        color: ok
                            ? MeshColors.verifiedGreen
                            : MeshColors.hazardAmber,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

