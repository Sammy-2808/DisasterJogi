import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesh_rescue/services/mesh_controller.dart';

final meshControllerProvider =
    NotifierProvider<MeshController, MeshUiState>(MeshController.new);

