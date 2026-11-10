import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_rescue/app/app.dart';
import 'package:mesh_rescue/app/providers.dart';
import 'package:mesh_rescue/services/mesh_controller.dart';

class _TestMeshController extends MeshController {
  @override
  MeshUiState build() {
    return const MeshUiState(
      bootStatus: MeshBootStatus.ready,
      deviceId: 'test1234',
      isAdvertising: true,
      isDiscovering: true,
    );
  }

  @override
  Future<void> initialize() async {}
}

void main() {
  testWidgets('Bottom navigation switches between all four tabs', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          meshControllerProvider.overrideWith(_TestMeshController.new),
        ],
        child: const MeshRescueApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mesh Home'), findsOneWidget);

    await tester.tap(find.text('Feed'));
    await tester.pumpAndSettle();
    expect(find.text('Alerts & Hazards Feed'), findsOneWidget);

    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    expect(find.text('Offline radar and map pins will live here.'), findsOneWidget);

    await tester.tap(find.text('Shelters'));
    await tester.pumpAndSettle();
    expect(find.text('Verified responder shelters will live here.'), findsOneWidget);
    expect(find.byIcon(Icons.shield), findsWidgets);
  });
}
