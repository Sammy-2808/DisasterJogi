import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesh_rescue/app/providers.dart';
import 'package:mesh_rescue/app/theme.dart';
import 'package:mesh_rescue/services/mesh_controller.dart';
import 'package:mesh_rescue/ui/debug/debug_screen.dart';
import 'package:mesh_rescue/ui/feed/feed_screen.dart';
import 'package:mesh_rescue/ui/home/home_screen.dart';
import 'package:mesh_rescue/ui/map/map_screen.dart';
import 'package:mesh_rescue/ui/onboarding/permissions_screen.dart';
import 'package:mesh_rescue/ui/onboarding/unsupported_device_screen.dart';
import 'package:mesh_rescue/ui/shelters/shelters_screen.dart';

class MeshRescueApp extends ConsumerWidget {
  const MeshRescueApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meshState = ref.watch(meshControllerProvider);
    final controller = ref.read(meshControllerProvider.notifier);

    final Widget home;
    switch (meshState.bootStatus) {
      case MeshBootStatus.checking:
        home = const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      case MeshBootStatus.unsupportedDevice:
        home = UnsupportedDeviceScreen(
          status: meshState.playServicesStatus,
          onRetry: () => controller.recheckAndStart(),
        );
      case MeshBootStatus.needsPermissions:
        home = PermissionsScreen(
          permissionsState: meshState.permissionsState,
          onRequestPermissions: () => controller.requestPermissionsAndStart(),
          onOpenLocationSettings: () => controller.openLocationSettings(),
          onOpenAppSettings: () => controller.openAppSettings(),
          onRecheck: () => controller.recheckAndStart(),
        );
      case MeshBootStatus.error:
        home = Scaffold(
          appBar: AppBar(title: const Text('MeshRescue')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber, size: 56, color: MeshColors.sosRed),
                  const SizedBox(height: 12),
                  Text(meshState.errorMessage ?? 'Mesh startup error'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => controller.recheckAndStart(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        );
      case MeshBootStatus.ready:
        home = const AppShell();
    }

    return MaterialApp(
      title: 'MeshRescue',
      debugShowCheckedModeBanner: false,
      theme: buildMeshTheme(),
      home: home,
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  static const List<Widget> _screens = <Widget>[
    HomeScreen(),
    FeedScreen(),
    MapScreen(),
    SheltersScreen(),
  ];

  static const List<String> _titles = <String>[
    'MeshRescue',
    'Mesh Feed',
    'Radar & Map',
    'Shelters',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        actions: [
          IconButton(
            tooltip: 'Mesh Debug',
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DebugScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'Feed',
          ),
          NavigationDestination(
            icon: Icon(Icons.radar_outlined),
            selectedIcon: Icon(Icons.radar),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.shield_outlined),
            selectedIcon: Icon(Icons.shield),
            label: 'Shelters',
          ),
        ],
      ),
    );
  }
}
