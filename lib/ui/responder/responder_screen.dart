import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesh_rescue/app/providers.dart';
import 'package:mesh_rescue/app/theme.dart';
import 'package:mesh_rescue/crypto/demo_responder_key.dart';
import 'package:mesh_rescue/engine/models/enums.dart';

class ResponderScreen extends ConsumerStatefulWidget {
  const ResponderScreen({super.key});

  @override
  ConsumerState<ResponderScreen> createState() => _ResponderScreenState();
}

class _ResponderScreenState extends ConsumerState<ResponderScreen> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _keyController =
      TextEditingController(text: 'school-ward-12');
  final TextEditingController _nameController =
      TextEditingController(text: 'Govt High School Relief Camp');
  final TextEditingController _capacityController =
      TextEditingController(text: '200');
  final TextEditingController _noteController =
      TextEditingController(text: 'Gate 2 open');
  late final TextEditingController _latController;
  late final TextEditingController _lngController;
  ShelterStatus _shelterStatus = ShelterStatus.open;
  final Set<String> _services = {'water', 'medical', 'food'};
  String? _pinError;

  @override
  void initState() {
    super.initState();
    final fix = ref.read(meshControllerProvider).locationFix;
    _latController = TextEditingController(
      text: fix != null ? fix.lat.toStringAsFixed(5) : '21.46800',
    );
    _lngController = TextEditingController(
      text: fix != null ? fix.lng.toStringAsFixed(5) : '83.98250',
    );
  }

  @override
  void dispose() {
    _pinController.dispose();
    _keyController.dispose();
    _nameController.dispose();
    _capacityController.dispose();
    _noteController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mesh = ref.watch(meshControllerProvider);
    final controller = ref.read(meshControllerProvider.notifier);
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    if (!mesh.isResponderUnlocked) {
      return Scaffold(
        appBar: AppBar(title: const Text('Responder Authority Mode')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.verified_user,
                  size: 64, color: MeshColors.primaryBlue),
              const SizedBox(height: 16),
              Text(
                'Unlock DEMO Responder Key',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'DEMO ONLY: Hackathon demonstration keypair for signing Verified Responder shelters and SOS acknowledgements. Demo PIN: ${DemoResponderKey.demoPin}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pinController,
                keyboardType: TextInputType.number,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Responder PIN',
                  errorText: _pinError,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  final ok = await controller.unlockResponderMode(
                    _pinController.text,
                  );
                  if (!mounted) return;
                  setState(() {
                    _pinError = ok ? null : 'Incorrect PIN (demo PIN: ${DemoResponderKey.demoPin})';
                  });
                },
                icon: const Icon(Icons.lock_open),
                label: const Text('Unlock Responder Mode'),
              ),
            ],
          ),
        ),
      );
    }

    final sosList = mesh.sosAlerts(nowSeconds: nowSec);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Responder Panel (DEMO)'),
        actions: [
          TextButton.icon(
            onPressed: () => controller.lockResponderMode(),
            icon: const Icon(Icons.lock, color: Colors.white),
            label: const Text('Lock', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: MeshColors.verifiedGreen, width: 1.5),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_user, color: MeshColors.verifiedGreen),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Active Authority: ${DemoResponderKey.demoResponderName} (${mesh.responderIdentity!.origin})',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('Publish / Update Verified Shelter',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _keyController,
                    decoration: const InputDecoration(
                      labelText: 'Shelter ID key (for updates)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Shelter name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _capacityController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Capacity',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      DropdownButton<ShelterStatus>(
                        value: _shelterStatus,
                        items: ShelterStatus.values
                            .map(
                              (s) => DropdownMenuItem(
                                value: s,
                                child: Text(s.wireName),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (v) {
                          if (v != null) setState(() => _shelterStatus = v);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: ['water', 'medical', 'food', 'power']
                        .map(
                          (svc) => FilterChip(
                            label: Text(svc),
                            selected: _services.contains(svc),
                            onSelected: (sel) {
                              setState(() {
                                if (sel) {
                                  _services.add(svc);
                                } else {
                                  _services.remove(svc);
                                }
                              });
                            },
                          ),
                        )
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Shelter Location (Coordinates)',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _latController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true, signed: true),
                          decoration: const InputDecoration(
                            labelText: 'Latitude',
                            hintText: 'e.g. 21.46800',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _lngController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true, signed: true),
                          decoration: const InputDecoration(
                            labelText: 'Longitude',
                            hintText: 'e.g. 83.98250',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        final fix = await controller.refreshLocation();
                        if (fix != null && mounted) {
                          setState(() {
                            _latController.text = fix.lat.toStringAsFixed(5);
                            _lngController.text = fix.lng.toStringAsFixed(5);
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Updated to current GPS coordinates.'),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.my_location, size: 16),
                      label: const Text('Use current GPS location'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _noteController,
                    decoration: const InputDecoration(
                      labelText: 'Entrance / contact note',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: MeshColors.verifiedGreen),
                    onPressed: () async {
                      final lat = double.tryParse(_latController.text.trim());
                      final lng = double.tryParse(_lngController.text.trim());
                      if (lat == null ||
                          lng == null ||
                          lat < -90 ||
                          lat > 90 ||
                          lng < -180 ||
                          lng > 180) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Please enter valid coordinates (Lat -90..90, Lng -180..180).',
                            ),
                          ),
                        );
                        return;
                      }

                      final cap = int.tryParse(_capacityController.text.trim()) ?? 100;
                      final ok = await controller.publishVerifiedShelter(
                        key: _keyController.text,
                        name: _nameController.text,
                        status: _shelterStatus,
                        capacity: cap,
                        services: _services.toList(),
                        note: _noteController.text,
                        customLat: lat,
                        customLng: lng,
                        fallbackLat: lat,
                        fallbackLng: lng,
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? 'Verified shelter signed & queued for broadcast!'
                                : 'Could not publish shelter (check fields).',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.shield),
                    label: const Text('Sign & Publish Verified Shelter'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Acknowledge Active SOS (${sosList.length})',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (sosList.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No SOS alerts received yet.'),
              ),
            )
          else
            for (final item in sosList) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item.payload.category.wireName.toUpperCase()} • ${item.payload.people} people • ${item.status.wireName}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (item.payload.note.isNotEmpty) Text(item.payload.note),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton(
                            onPressed: () => controller.publishResponderAck(
                              sosId: item.sos.id,
                              status: AckStatus.received,
                              note: 'Control Room received SOS',
                            ),
                            child: const Text('ACK Received'),
                          ),
                          FilledButton.tonal(
                            onPressed: () => controller.publishResponderAck(
                              sosId: item.sos.id,
                              status: AckStatus.dispatched,
                              note: 'Rescue unit en route',
                            ),
                            child: const Text('Dispatch Team'),
                          ),
                          OutlinedButton(
                            onPressed: () => controller.publishResponderAck(
                              sosId: item.sos.id,
                              status: AckStatus.resolved,
                              note: 'Rescued',
                            ),
                            child: const Text('Mark Resolved'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

