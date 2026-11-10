import 'package:mesh_rescue/crypto/trust_service.dart';
import 'package:mesh_rescue/domain/sos_state.dart';
import 'package:mesh_rescue/engine/models/enums.dart';
import 'package:mesh_rescue/engine/models/payloads.dart';
import 'package:mesh_rescue/transport/sim/sim_world.dart';
import 'package:test/test.dart';

void main() {
  group('SimWorld multi-hop & partition scenarios', () {
    test('5-node line topology A-B-C-D-E delivers SOS from A to E with trace', () async {
      final responderWorld = SimWorld(radioRange: 100.0, seed: 42);
      final responderId = await responderWorld.signer.loadKeyPairFromSeed(
        List<int>.filled(32, 77),
      );
      await responderWorld.dispose();

      final trust = TrustService([
        TrustedResponder(name: 'Control HQ (DEMO)', pub: responderId.publicKeyBase64),
      ]);
      final world = SimWorld(
        radioRange: 100.0,
        seed: 42,
        trustService: trust,
      );
      addTearDown(world.dispose);

      // Line spacing 80m (< 100m range), so only adjacent nodes link: A-B-C-D-E.
      final a = await world.addNode(label: 'A', x: 0, y: 0);
      final b = await world.addNode(label: 'B', x: 80, y: 0);
      final c = await world.addNode(label: 'C', x: 160, y: 0);
      final d = await world.addNode(label: 'D', x: 240, y: 0);
      final e = await world.addNode(
        label: 'E',
        x: 320,
        y: 0,
        identity: responderId,
      );

      await world.step(); // establish links & HELLO/INV

      final sos = await a.engine.publishSos(
        payload: const SosPayload(
          category: SosCategory.trapped,
          people: 3,
          note: '2nd floor',
        ),
        lat: 21.4669,
        lng: 83.9812,
      );

      await world.runSteps(6);

      // Verify E received A's SOS through 4 hops (A->B->C->D->E).
      final sosAtE = await e.store.getMessage(sos.id);
      expect(sosAtE, isNotNull);
      expect(sosAtE!.envelope.hops, 4);
      expect(sosAtE.envelope.ttl, 6);
      expect(await b.store.hasMessage(sos.id), isTrue);
      expect(await c.store.hasMessage(sos.id), isTrue);
      expect(await d.store.hasMessage(sos.id), isTrue);

      // E (responder) ACKs A's SOS -> propagates back E->D->C->B->A!
      await e.engine.publishAck(
        sosId: sos.id,
        payload: const AckPayload(
          status: AckStatus.dispatched,
          note: 'Rescue boat dispatched',
        ),
      );
      await world.runSteps(6);

      final acksAtA = await a.store.getMessagesByRefId(sos.id);
      final sosStateAtA = deriveSosState(
        sos: (await a.store.getMessage(sos.id))!,
        candidateAcks: acksAtA,
        trustService: trust,
        nowSeconds: world.clock.nowSeconds(),
      );
      expect(sosStateAtA.status, SosStatus.acknowledged);
      expect(sosStateAtA.ackStatus, AckStatus.dispatched);

      // Print propagation trace for Phase 2 acceptance evidence.
      // ignore: avoid_print
      print('--- 5-Node Line Propagation Trace (A-B-C-D-E) ---');
      for (final event in world.trace) {
        if (event.messageId != null) {
          // ignore: avoid_print
          print(event);
        }
      }
    });

    test('partition healing: moving data-mule bridges two islands to convergence', () async {
      final world = SimWorld(radioRange: 100.0, seed: 99);
      addTearDown(world.dispose);

      // Island 1 around x=0..60
      final a = await world.addNode(label: 'A', x: 0, y: 0);
      final b = await world.addNode(label: 'B', x: 60, y: 0);
      // Island 2 around x=400..460 (far out of range)
      final d = await world.addNode(label: 'D', x: 400, y: 0);
      final e = await world.addNode(label: 'E', x: 460, y: 0);
      // Mobile data-mule starts on Island 1
      final mule = await world.addNode(label: 'Mule', x: 30, y: 0);

      await world.step();

      final sosA = await a.engine.publishSos(
        payload: const SosPayload(category: SosCategory.flood, people: 4),
        lat: 21.46,
        lng: 83.98,
      );
      final hazardE = await e.engine.publishHazard(
        payload: const HazardPayload(kind: HazardKind.collapse, severity: 5),
        lat: 21.47,
        lng: 83.99,
      );
      await world.runSteps(4);

      expect(await mule.store.hasMessage(sosA.id), isTrue);
      expect(await d.store.hasMessage(sosA.id), isFalse);
      expect(await a.store.hasMessage(hazardE.id), isFalse);

      // Mule leaves Island 1 (out of range of everyone) then arrives at Island 2.
      world.moveNode(mule.id, 230, 0);
      await world.runSteps(2);
      world.moveNode(mule.id, 430, 0);
      await world.runSteps(5);

      expect(await d.store.hasMessage(sosA.id), isTrue);
      expect(await e.store.hasMessage(sosA.id), isTrue);
      expect(await mule.store.hasMessage(hazardE.id), isTrue);

      // Mule travels back to Island 1 carrying E's hazard.
      world.moveNode(mule.id, 30, 0);
      await world.runSteps(5);

      expect(await a.store.hasMessage(hazardE.id), isTrue);
      expect(await b.store.hasMessage(hazardE.id), isTrue);
    });

    test('packet loss recovery via periodic INV/REQ and SOS rebroadcast', () async {
      final world = SimWorld(
        radioRange: 100.0,
        lossProbability: 0.25,
        seed: 2026,
      );
      addTearDown(world.dispose);

      final a = await world.addNode(label: 'A', x: 0, y: 0);
      final b = await world.addNode(label: 'B', x: 75, y: 0);
      final c = await world.addNode(label: 'C', x: 150, y: 0);

      await world.step();

      final sos = await a.engine.publishSos(
        payload: const SosPayload(category: SosCategory.fire, people: 2),
        lat: 21.4669,
        lng: 83.9812,
      );

      // Advance enough time (steps of 20s) for periodic INV (60s) and SOS rebroadcast (30s)
      await world.runSteps(10, stepSeconds: 20);

      expect(await b.store.hasMessage(sos.id), isTrue);
      expect(await c.store.hasMessage(sos.id), isTrue);
    });
  });
}

