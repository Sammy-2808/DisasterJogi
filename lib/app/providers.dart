import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesh_rescue/services/mesh_controller.dart';

final meshControllerProvider =
    NotifierProvider<MeshController, MeshUiState>(MeshController.new);

final meshStatusProvider = Provider<({int peers, int relayed, bool batterySaver})>((ref) {
  final s = ref.watch(meshControllerProvider);
  return (
    peers: s.peers.length,
    relayed: s.relayedCount,
    batterySaver: s.batterySaver,
  );
});
