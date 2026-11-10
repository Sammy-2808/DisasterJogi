import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mesh_rescue/app/theme.dart';
import 'package:mesh_rescue/engine/models/enums.dart';
import 'package:mesh_rescue/engine/models/payloads.dart';
import 'package:mesh_rescue/transport/sim/sim_world.dart';

class SimulatorScreen extends StatefulWidget {
  const SimulatorScreen({super.key});

  @override
  State<SimulatorScreen> createState() => _SimulatorScreenState();
}

class _SimulatorScreenState extends State<SimulatorScreen> {
  SimWorld? _world;
  String? _trackedSosId;
  bool _playing = false;
  bool _randomWalk = false;
  bool _partitionMode = false;
  String? _muleId;
  Timer? _timer;
  int _steps = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_setupWorld(partition: false));
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_world?.dispose());
    super.dispose();
  }

  Future<void> _setupWorld({required bool partition}) async {
    _timer?.cancel();
    _playing = false;
    final prev = _world;
    final world = SimWorld(radioRange: 95.0, seed: 42);

    if (partition) {
      // Two islands (x=30..110 and x=340..420) plus moving data mule.
      for (var i = 0; i < 9; i++) {
        await world.addNode(
          label: 'L$i',
          x: 35.0 + (i % 3) * 45.0,
          y: 70.0 + (i ~/ 3) * 65.0,
        );
      }
      for (var i = 0; i < 10; i++) {
        await world.addNode(
          label: 'R$i',
          x: 320.0 + (i % 3) * 45.0,
          y: 65.0 + (i ~/ 3) * 55.0,
        );
      }
      final mule = await world.addNode(label: 'Mule', x: 95, y: 140);
      _muleId = mule.id;
    } else {
      // 20-node grid/mesh across a 460x280 field.
      final rng = math.Random(42);
      for (var i = 0; i < 20; i++) {
        final col = i % 5;
        final row = i ~/ 5;
        await world.addNode(
          label: 'N$i',
          x: 45.0 + col * 88.0 + (rng.nextDouble() - 0.5) * 18,
          y: 45.0 + row * 65.0 + (rng.nextDouble() - 0.5) * 18,
        );
      }
      _muleId = null;
    }

    await world.step();
    await prev?.dispose();
    if (!mounted) {
      await world.dispose();
      return;
    }
    setState(() {
      _world = world;
      _partitionMode = partition;
      _trackedSosId = null;
      _steps = 0;
    });
  }

  void _togglePlay() {
    setState(() {
      _playing = !_playing;
    });
    if (_playing) {
      _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        unawaited(_advanceStep());
      });
    } else {
      _timer?.cancel();
    }
  }

  Future<void> _advanceStep() async {
    final world = _world;
    if (world == null) return;
    if (_partitionMode && _muleId != null) {
      // Sweep the data mule back and forth across the gap between islands.
      final mule = world.nodes.firstWhere((n) => n.id == _muleId);
      final targetX = 95.0 + 115.0 * (1 - math.cos(_steps * 0.35));
      world.moveNode(mule.id, targetX, 140);
    } else if (_randomWalk) {
      world.randomWalkAll(maxDelta: 12, width: 440, height: 270);
    }
    await world.step();
    if (!mounted) return;
    setState(() {
      _steps++;
    });
  }

  Future<void> _triggerSosAtNode0() async {
    final world = _world;
    if (world == null || world.nodes.isEmpty) return;
    final origin = world.nodes.first;
    final msg = await origin.engine.publishSos(
      payload: const SosPayload(
        category: SosCategory.trapped,
        people: 2,
        note: 'Simulated SOS',
      ),
      lat: 21.4669,
      lng: 83.9812,
    );
    setState(() {
      _trackedSosId = msg.id;
    });
    await _advanceStep();
  }

  @override
  Widget build(BuildContext context) {
    final world = _world;
    return Scaffold(
      appBar: AppBar(title: const Text('20-Node Mesh Simulator')),
      body: world == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: AspectRatio(
                      aspectRatio: 460 / 290,
                      child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D1B2A),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: MeshColors.inkPrimary, width: 2),
                      ),
                      child: FutureBuilder<Set<String>>(
                        future: _nodesHoldingTracked(world),
                        builder: (context, snap) {
                          return CustomPaint(
                            painter: _SimPainter(
                              world: world,
                              holdingSos: snap.data ?? const <String>{},
                              muleId: _muleId,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: MeshColors.sosRed),
                        onPressed: _triggerSosAtNode0,
                        icon: const Icon(Icons.sos),
                        label: const Text('SOS @ Node 0'),
                      ),
                      FilledButton.icon(
                        onPressed: _togglePlay,
                        icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                        label: Text(_playing ? 'Pause' : 'Play'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _advanceStep,
                        icon: const Icon(Icons.skip_next),
                        label: Text('Step ($_steps)'),
                      ),
                      OutlinedButton(
                        onPressed: () =>
                            _setupWorld(partition: !_partitionMode),
                        child: Text(
                          _partitionMode
                              ? 'Switch: 20-Node Grid'
                              : 'Preset: Partition + Mule',
                        ),
                      ),
                      FilterChip(
                        label: const Text('Random Walk'),
                        selected: _randomWalk,
                        onSelected: (v) => setState(() => _randomWalk = v),
                      ),
                      OutlinedButton(
                        onPressed: () async {
                          final target = world.nodes.length > 5
                              ? world.nodes[5]
                              : world.nodes.last;
                          await world.setNodeOnline(target.id, !target.online);
                          await _advanceStep();
                        },
                        child: const Text('Toggle Node 5'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      Text(
                        'Recent Propagation Trace (${world.trace.length} events)',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      for (final ev in world.trace.reversed.take(25))
                        Text(
                          ev.toString(),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Future<Set<String>> _nodesHoldingTracked(SimWorld world) async {
    final id = _trackedSosId;
    if (id == null) return const <String>{};
    final out = <String>{};
    for (final n in world.nodes) {
      if (await n.store.hasMessage(id)) {
        out.add(n.id);
      }
    }
    return out;
  }
}

class _SimPainter extends CustomPainter {
  final SimWorld world;
  final Set<String> holdingSos;
  final String? muleId;

  const _SimPainter({
    required this.world,
    required this.holdingSos,
    required this.muleId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 460.0;
    final sy = size.height / 290.0;

    final linkPaint = Paint()
      ..color = const Color(0xFF415A77)
      ..strokeWidth = 1.4;

    final nodes = world.nodes;
    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        final a = nodes[i];
        final b = nodes[j];
        if (!a.online || !b.online) continue;
        final dx = a.x - b.x;
        final dy = a.y - b.y;
        if (math.sqrt(dx * dx + dy * dy) <= world.radioRange) {
          canvas.drawLine(
            Offset(a.x * sx, a.y * sy),
            Offset(b.x * sx, b.y * sy),
            linkPaint,
          );
        }
      }
    }

    for (final n in nodes) {
      final pos = Offset(n.x * sx, n.y * sy);
      final isMule = n.id == muleId;
      final Color fill;
      if (!n.online) {
        fill = Colors.grey.shade600;
      } else if (holdingSos.contains(n.id)) {
        fill = const Color(0xFFFF5252);
      } else if (isMule) {
        fill = const Color(0xFFFFB300);
      } else {
        fill = const Color(0xFF4FC3F7);
      }
      canvas.drawCircle(pos, isMule ? 10 : 8, Paint()..color = fill);

      final tp = TextPainter(
        text: TextSpan(
          text: n.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy + 10));
    }
  }

  @override
  bool shouldRepaint(covariant _SimPainter oldDelegate) => true;
}

