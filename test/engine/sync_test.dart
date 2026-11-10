import 'package:mesh_rescue/engine/models/enums.dart';
import 'package:mesh_rescue/engine/models/frame.dart';
import 'package:mesh_rescue/engine/models/payloads.dart';
import 'package:mesh_rescue/transport/sim/sim_world.dart';
import 'package:test/test.dart';

void main() {
  group('HELLO/INV/REQ/MSG anti-entropy sync', () {
    test('two nodes with disjoint histories converge cleanly on connect', () async {
      final world = SimWorld(radioRange: 100.0, seed: 7);
      addTearDown(world.dispose);

      // Start out of range so they accumulate disjoint histories.
      final a = await world.addNode(label: 'A', x: 0, y: 0);
      final b = await world.addNode(label: 'B', x: 500, y: 0);

      for (var i = 0; i < 6; i++) {
        await a.engine.publishHazard(
          payload: HazardPayload(kind: HazardKind.flood, severity: 3, note: 'A-$i'),
          lat: 21.4 + i * 0.001,
          lng: 83.9,
        );
      }
      for (var i = 0; i < 4; i++) {
        await b.engine.publishSos(
          payload: SosPayload(category: SosCategory.medical, people: i + 1, note: 'B-$i'),
          lat: 21.5 + i * 0.001,
          lng: 83.9,
        );
      }

      expect(await a.store.countMessages(), 6);
      expect(await b.store.countMessages(), 4);

      // Bring B inside A's radio range.
      world.moveNode(b.id, 50, 0);
      await world.runSteps(4);

      expect(await a.store.countMessages(), 10);
      expect(await b.store.countMessages(), 10);
    });

    test('INV chunking handles > 50 items under 4096-byte frame limit', () async {
      final world = SimWorld(radioRange: 100.0, seed: 11);
      addTearDown(world.dispose);

      final a = await world.addNode(label: 'A', x: 0, y: 0);
      final b = await world.addNode(label: 'B', x: 500, y: 0);

      // Generate 75 distinct items across 8 different simulated origins (10/min rate limit).
      for (var i = 0; i < 75; i++) {
        final originSeed = List<int>.filled(32, 10 + (i ~/ 9));
        final id = await world.signer.loadKeyPairFromSeed(originSeed);
        await a.engine.publishHazard(
          payload: HazardPayload(kind: HazardKind.roadBlocked, severity: 2, note: 'H-$i'),
          lat: 21.4 + i * 0.0001,
          lng: 83.9,
          signingIdentity: id,
        );
      }
      expect(await a.store.countMessages(), 75);

      world.moveNode(b.id, 50, 0);
      await world.runSteps(6);

      expect(await b.store.countMessages(), 75);
    });

    test('unsupported HELLO version closes link', () async {
      final world = SimWorld(radioRange: 100.0, seed: 12);
      addTearDown(world.dispose);

      final a = await world.addNode(label: 'A', x: 0, y: 0);
      final b = await world.addNode(label: 'B', x: 50, y: 0);
      await world.step();
      expect(a.engine.connectedPeers, contains(b.id));

      await a.engine.receiveFrame(
        b.id,
        FrameCodec.encode(
          HelloFrame(
            v: 99,
            deviceId: b.id,
            pub: b.identity.publicKeyBase64,
          ),
        ),
      );
      expect(a.engine.connectedPeers, isNot(contains(b.id)));
    });
  });
}

