import 'package:flutter/material.dart';
import 'package:mesh_rescue/app/theme.dart';
import 'package:mesh_rescue/services/platform_checks.dart';

class UnsupportedDeviceScreen extends StatelessWidget {
  final PlayServicesStatus? status;
  final VoidCallback onRetry;

  const UnsupportedDeviceScreen({
    super.key,
    required this.status,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MeshRescue')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.error_outline,
                size: 72,
                color: MeshColors.sosRed,
              ),
              const SizedBox(height: 20),
              Text(
                'Google Play Services Required',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'MeshRescue uses Android Nearby Connections to form an offline Bluetooth & Wi-Fi mesh. '
                'This device does not currently have working Google Play Services.',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              if (status != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Status: ${status!.statusMessage} (code ${status!.statusCode})',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Check Again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

