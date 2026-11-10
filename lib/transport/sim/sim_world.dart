import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mesh_rescue/crypto/signer.dart';
import 'package:mesh_rescue/crypto/trust_service.dart';
import 'package:mesh_rescue/data/message_store.dart';
import 'package:mesh_rescue/engine/clock.dart';
import 'package:mesh_rescue/engine/mesh_engine.dart';
import 'package:mesh_rescue/engine/models/frame.dart';
import 'package:mesh_rescue/transport/sim/sim_transport.dart';

class SimTraceEvent {
  final int step;
  final int timeSec;
  final String fromId;
  final String toId;
  final String frameLabel;
  final String? messageId;
  final int? hops;
  final int? ttl;
  final bool droppedByRadio;

  const SimTraceEvent({
    required this.step,
    required this.timeSec,
    required this.fromId,
    required this.toId,
    required this.frameLabel,
    this.messageId,
    this.hops,
    this.ttl,
    this.droppedByRadio = false,
  });

  @override
  String toString() {
    final msgPart = messageId == null
        ? frameLabel
        : '$frameLabel(id=${messageId!.substring(0, 8)}, ttl=$ttl, hops=$hops)';
    final status = droppedByRadio ? ' [RADIO_DROP]' : '';
    return '[step=$step t=${timeSec}s] $fromId -> $toId : $msgPart$status';
  }
}

class SimNode {
  final String label;
  final IdentityKeyPair identity;
  final InMemoryMessageStore store;
  final SimTransport transport;
  final MeshEngine engine;

  double x;
  double y;
  bool online;

  SimNode({
    required this.label,
    required this.identity,
    required this.store,
    required this.transport,
    required this.engine,
    required this.x,
    required this.y,
    this.online = true,
  });

  String get id => identity.origin;
}

class _QueuedDelivery {
  final String fromId;
  final String toId;
  final Uint8List bytes;

  const _QueuedDelivery({
    required this.fromId,
    required this.toId,
    required this.bytes,
  });
}

/// Deterministic virtual radio world running real [MeshEngine] instances.
class SimWorld {
  final double radioRange;
  final double lossProbability;
  final int? maxDegree;
  final FakeClock clock;
  final Ed25519Signer signer;
  final TrustService trustService;
  final math.Random _random;

  final List<SimNode> _nodes = <SimNode>[];
  final Map<String, SimNode> _nodesById = <String, SimNode>{};
  final Map<String, Set<String>> _links = <String, Set<String>>{};
  final List<_QueuedDelivery> _radioQueue = <_QueuedDelivery>[];
  final List<SimTraceEvent> trace = <SimTraceEvent>[];
  int _currentStep = 0;

  SimWorld({
    this.radioRange = 100.0,
    this.lossProbability = 0.0,
    this.maxDegree,
    int seed = 42,
    FakeClock? clock,
    TrustService? trustService,
  })  : clock = clock ?? FakeClock(),
        signer = Ed25519Signer(),
        trustService = trustService ?? TrustService.empty(),
        _random = math.Random(seed);

  List<SimNode> get nodes => List<SimNode>.unmodifiable(_nodes);

  Future<SimNode> addNode({
    required String label,
    required double x,
    required double y,
    IdentityKeyPair? identity,
    bool online = true,
    bool autoStart = true,
  }) async {
    final resolvedIdentity = identity ?? await _deterministicIdentity();
    final store = InMemoryMessageStore();
    late final SimTransport transport;
    transport = SimTransport(
      deviceId: resolvedIdentity.origin,
      onSend: (from, to, bytes) async {
        _radioQueue.add(_QueuedDelivery(fromId: from, toId: to, bytes: bytes));
      },
      onDisconnectRequested: (from, to) async {
        _unlink(from, to);
      },
    );
    final engine = MeshEngine(
      transport: transport,
      store: store,
      signer: signer,
      identity: resolvedIdentity,
      trustService: trustService,
      clock: clock,
    );
    final node = SimNode(
      label: label,
      identity: resolvedIdentity,
      store: store,
      transport: transport,
      engine: engine,
      x: x,
      y: y,
      online: online,
    );
    _nodes.add(node);
    _nodesById[node.id] = node;
    _links[node.id] = <String>{};
    if (autoStart && online) {
      await engine.start();
    }
    return node;
  }

  Future<IdentityKeyPair> _deterministicIdentity() async {
    final seed = List<int>.generate(32, (_) => _random.nextInt(256));
    return signer.loadKeyPairFromSeed(seed);
  }

  Future<void> setNodeOnline(String nodeId, bool online) async {
    final node = _nodesById[nodeId];
    if (node == null || node.online == online) return;
    node.online = online;
    if (online) {
      await node.engine.start();
    } else {
      await node.engine.stop();
      final peers = _links[nodeId]?.toList() ?? const [];
      for (final p in peers) {
        _unlink(nodeId, p);
      }
    }
  }

  void moveNode(String nodeId, double x, double y) {
    final node = _nodesById[nodeId];
    if (node == null) return;
    node.x = x;
    node.y = y;
  }

  void randomWalkAll({double maxDelta = 10.0, double width = 500, double height = 500}) {
    for (final n in _nodes) {
      if (!n.online) continue;
      n.x = (n.x + (_random.nextDouble() * 2 - 1) * maxDelta).clamp(0.0, width);
      n.y = (n.y + (_random.nextDouble() * 2 - 1) * maxDelta).clamp(0.0, height);
    }
  }

  /// Updates bidirectional peer links based on Euclidean distance <= [radioRange].
  Future<void> reconcileTopology() async {
    for (var i = 0; i < _nodes.length; i++) {
      for (var j = i + 1; j < _nodes.length; j++) {
        final a = _nodes[i];
        final b = _nodes[j];
        final shouldConnect = a.online &&
            b.online &&
            _distance(a, b) <= radioRange;
        final isLinked = _links[a.id]!.contains(b.id);
        if (shouldConnect && !isLinked) {
          final cap = maxDegree;
          if (cap != null &&
              (_links[a.id]!.length >= cap || _links[b.id]!.length >= cap)) {
            continue;
          }
          _links[a.id]!.add(b.id);
          _links[b.id]!.add(a.id);
          a.transport.simulatePeerConnected(b.id, endpointName: b.label);
          b.transport.simulatePeerConnected(a.id, endpointName: a.label);
        } else if (!shouldConnect && isLinked) {
          _unlink(a.id, b.id);
        }
      }
    }
  }

  void _unlink(String aId, String bId) {
    _links[aId]?.remove(bId);
    _links[bId]?.remove(aId);
    _nodesById[aId]?.transport.simulatePeerDisconnected(bId);
    _nodesById[bId]?.transport.simulatePeerDisconnected(aId);
  }

  /// Advances simulation by one discrete round: topology check, drain radio
  /// queue, run node maintenance ticks, and settle async microtasks.
  Future<int> step({int advanceSeconds = 1}) async {
    _currentStep++;
    clock.advanceSeconds(advanceSeconds);
    await reconcileTopology();
    await _drainMicrotasks();

    var deliveredOrDropped = 0;
    // Drain waves generated within this step (bounded to prevent runaway loops).
    for (var wave = 0; wave < 32; wave++) {
      if (_radioQueue.isEmpty) break;
      final batch = List<_QueuedDelivery>.from(_radioQueue);
      _radioQueue.clear();
      for (final item in batch) {
        final from = _nodesById[item.fromId];
        final to = _nodesById[item.toId];
        if (from == null || to == null) continue;
        if (!from.online || !to.online) continue;
        if (!(_links[from.id]?.contains(to.id) ?? false)) continue;

        final dropped = lossProbability > 0 && _random.nextDouble() < lossProbability;
        _recordTrace(from, to, item.bytes, droppedByRadio: dropped);
        deliveredOrDropped++;
        if (!dropped) {
          to.transport.deliverIncomingFrame(from.id, item.bytes);
        }
      }
      await _drainMicrotasks();
    }

    for (final node in _nodes) {
      if (node.online) {
        await node.engine.tick();
      }
    }
    await _drainMicrotasks();

    // Flush any frames produced during engine.tick().
    while (_radioQueue.isNotEmpty) {
      final batch = List<_QueuedDelivery>.from(_radioQueue);
      _radioQueue.clear();
      for (final item in batch) {
        final from = _nodesById[item.fromId];
        final to = _nodesById[item.toId];
        if (from == null || to == null || !from.online || !to.online) continue;
        if (!(_links[from.id]?.contains(to.id) ?? false)) continue;
        final dropped = lossProbability > 0 && _random.nextDouble() < lossProbability;
        _recordTrace(from, to, item.bytes, droppedByRadio: dropped);
        deliveredOrDropped++;
        if (!dropped) {
          to.transport.deliverIncomingFrame(from.id, item.bytes);
        }
      }
      await _drainMicrotasks();
    }

    return deliveredOrDropped;
  }

  Future<void> runSteps(int count, {int stepSeconds = 1}) async {
    for (var i = 0; i < count; i++) {
      await step(advanceSeconds: stepSeconds);
    }
  }

  void _recordTrace(
    SimNode from,
    SimNode to,
    Uint8List bytes, {
    required bool droppedByRadio,
  }) {
    String label = 'UNKNOWN';
    String? messageId;
    int? hops;
    int? ttl;
    try {
      final frame = FrameCodec.decode(bytes);
      switch (frame) {
        case HelloFrame():
          label = 'HELLO';
        case InvFrame():
          label = 'INV(${frame.items.length})';
        case ReqFrame():
          label = 'REQ(${frame.ids.length})';
        case PingFrame():
          label = 'PING';
        case UnknownFrame():
          label = 'UNKNOWN';
        case MsgFrame(:final envelope):
          label = 'MSG/${envelope.type.wireName}';
          messageId = envelope.id;
          hops = envelope.hops;
          ttl = envelope.ttl;
      }
    } catch (_) {
      label = 'RAW(${bytes.length}B)';
    }

    trace.add(
      SimTraceEvent(
        step: _currentStep,
        timeSec: clock.nowSeconds(),
        fromId: from.label,
        toId: to.label,
        frameLabel: label,
        messageId: messageId,
        hops: hops,
        ttl: ttl,
        droppedByRadio: droppedByRadio,
      ),
    );
  }

  double _distance(SimNode a, SimNode b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  Future<void> _drainMicrotasks() async {
    for (var i = 0; i < 16; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> dispose() async {
    for (final n in _nodes) {
      await n.engine.dispose();
      await n.transport.dispose();
    }
    _nodes.clear();
    _nodesById.clear();
    _links.clear();
    _radioQueue.clear();
  }
}
