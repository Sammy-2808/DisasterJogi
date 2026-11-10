import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_rescue/app/app.dart';
import 'package:mesh_rescue/app/providers.dart';
import 'package:mesh_rescue/crypto/signer.dart';
import 'package:mesh_rescue/crypto/trust_service.dart';
import 'package:mesh_rescue/data/message_store.dart';
import 'package:mesh_rescue/engine/models/envelope.dart';
import 'package:mesh_rescue/engine/models/enums.dart';
import 'package:mesh_rescue/services/location_service.dart';
import 'package:mesh_rescue/services/mesh_controller.dart';
import 'package:mesh_rescue/ui/radar/radar_view.dart';
import 'package:mesh_rescue/ui/widgets/hold_sos_button.dart';

class _TestMeshController extends MeshController {
  final MeshUiState initial;
  int sosSentCount = 0;

  _TestMeshController(this.initial);

  @override
  MeshUiState build() => initial;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> sendSos({
    required SosCategory category,
    required int people,
    String note = '',
    String? contact,
  }) async {
    sosSentCount++;
  }
}

void main() {
  testWidgets('Tabs switch cleanly, RadarView renders without offline pin canvas, and HoldSosButton resists accidental taps', (tester) async {
    final controller = _TestMeshController(
      const MeshUiState(
        bootStatus: MeshBootStatus.ready,
        deviceId: 'test1234',
        isAdvertising: true,
        isDiscovering: true,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          meshControllerProvider.overrideWith(() => controller),
        ],
        child: const MeshRescueApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HoldSosButton), findsOneWidget);

    // Quick tap must NOT trigger SOS (must hold 2s).
    await tester.tap(find.byType(HoldSosButton));
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.sosSentCount, 0);

    // Switch to Feed, Map (pure RadarView), and Shelters tabs.
    await tester.tap(find.text('Feed'));
    await tester.pumpAndSettle();
    expect(find.text('No Mesh Alerts Yet'), findsOneWidget);

    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    // Pure RadarView with no offline pin canvas
    expect(find.byType(RadarView), findsOneWidget);
    expect(find.text('Offline Pin Canvas'), findsNothing);

    await tester.tap(find.text('Shelters'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Verified Responder Shelters'), findsOneWidget);
    expect(find.byIcon(Icons.shield), findsWidgets);
  });

  testWidgets('Shelters and Radar map strictly show verified responder shelters, completely excluding unverified/forged shelters', (tester) async {
    final signer = Ed25519Signer();
    final responder = await signer.loadKeyPairFromSeed(List<int>.filled(32, 3));
    final attacker = await signer.loadKeyPairFromSeed(List<int>.filled(32, 9));
    final trust = TrustService([
      TrustedResponder(name: 'Control HQ', pub: responder.publicKeyBase64),
    ]);
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final verifiedEnv = await signer.signEnvelope(
      Envelope(
        id: 'sh-good',
        type: MessageType.shelter,
        origin: responder.origin,
        originPub: responder.publicKeyBase64,
        ts: nowSec,
        lat: 21.467,
        lng: 83.982,
        refId: null,
        payload: const {
          'key': 'good-1',
          'name': 'Govt School Camp',
          'status': 'OPEN',
          'capacity': 200,
          'services': ['water'],
          'seq': 1,
        },
        sig: '',
        ttl: 10,
        hops: 1,
      ),
      responder,
    );

    final forgedEnv = await signer.signEnvelope(
      Envelope(
        id: 'sh-forged',
        type: MessageType.shelter,
        origin: attacker.origin,
        originPub: attacker.publicKeyBase64,
        ts: nowSec,
        lat: 21.469,
        lng: 83.985,
        refId: null,
        payload: const {
          'key': 'bad-1',
          'name': 'Suspicious Trap Building',
          'status': 'OPEN',
          'capacity': 500,
          'services': ['food'],
          'seq': 1,
        },
        sig: '',
        ttl: 10,
        hops: 1,
      ),
      attacker,
    );

    final controller = _TestMeshController(
      MeshUiState(
        bootStatus: MeshBootStatus.ready,
        deviceId: 'test1234',
        trustService: trust,
        locationFix: GeoFix(lat: 21.4669, lng: 83.9812, timestampSeconds: nowSec),
        messages: [
          StoredMessage(
            envelope: verifiedEnv,
            receivedAt: nowSec,
            geohash: 'tgcu123',
            trust: TrustTier.verifiedResponder,
            isLocal: false,
          ),
          StoredMessage(
            envelope: forgedEnv,
            receivedAt: nowSec,
            geohash: 'tgcu123',
            trust: TrustTier.unverified,
            isLocal: false,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          meshControllerProvider.overrideWith(() => controller),
        ],
        child: const MeshRescueApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Shelters'));
    await tester.pumpAndSettle();

    // Verified shelter shown, forged shelter completely absent and no toggle for unverified.
    expect(find.text('Govt School Camp'), findsOneWidget);
    expect(find.text('Verified safe shelter listing'), findsOneWidget);
    expect(find.text('Suspicious Trap Building'), findsNothing);
    expect(find.text('Show community-reported (Unverified)'), findsNothing);

    // Switch to Map tab: verified shelter is displayed on the radar map, forged shelter is not
    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    expect(find.byType(RadarView), findsOneWidget);
    expect(find.textContaining('Shelter: Govt School Camp'), findsOneWidget);
    expect(find.textContaining('Suspicious Trap Building'), findsNothing);
  });

  testWidgets('HoldSosButton triggers after continuous 2s hold', (tester) async {
    final controller = _TestMeshController(
      const MeshUiState(
        bootStatus: MeshBootStatus.ready,
        deviceId: 'test1234',
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          meshControllerProvider.overrideWith(() => controller),
        ],
        child: const MeshRescueApp(),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldSosButton)),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 2100));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.sosSentCount, 1);
  });
}
