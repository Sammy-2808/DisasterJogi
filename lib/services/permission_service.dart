import 'package:geolocator/geolocator.dart';
import 'package:mesh_rescue/services/platform_checks.dart';
import 'package:permission_handler/permission_handler.dart';

class MeshPermissionsState {
  final bool allPermissionsGranted;
  final bool permanentlyDenied;
  final bool locationServiceEnabled;
  final int androidSdkInt;
  final Map<Permission, PermissionStatus> statuses;

  const MeshPermissionsState({
    required this.allPermissionsGranted,
    required this.permanentlyDenied,
    required this.locationServiceEnabled,
    required this.androidSdkInt,
    required this.statuses,
  });

  bool get isReady => allPermissionsGranted && locationServiceEnabled;
}

class PermissionService {
  final PlatformChecks _platformChecks;

  PermissionService({PlatformChecks? platformChecks})
      : _platformChecks = platformChecks ?? PlatformChecks();

  Future<List<Permission>> requiredPermissions({int? sdkInt}) async {
    final sdk = sdkInt ?? await _platformChecks.getAndroidSdkInt();
    final perms = <Permission>[
      Permission.locationWhenInUse,
    ];
    if (sdk >= 31 || sdk == 0) {
      perms.addAll([
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
      ]);
    }
    if (sdk >= 33 || sdk == 0) {
      perms.add(Permission.nearbyWifiDevices);
    }
    return perms;
  }

  Future<MeshPermissionsState> checkCurrent() async {
    final sdk = await _platformChecks.getAndroidSdkInt();
    final perms = await requiredPermissions(sdkInt: sdk);
    final statuses = <Permission, PermissionStatus>{};
    for (final p in perms) {
      statuses[p] = await p.status;
    }
    final allGranted = statuses.values.every((s) => s.isGranted);
    final locationEnabled = await Geolocator.isLocationServiceEnabled();
    return MeshPermissionsState(
      allPermissionsGranted: allGranted,
      permanentlyDenied: false,
      locationServiceEnabled: locationEnabled,
      androidSdkInt: sdk,
      statuses: statuses,
    );
  }

  /// Note from permission_handler 13.x: `permanentlyDenied` on Android is only
  /// returned by `request()`, never by `status`.
  Future<MeshPermissionsState> requestAll() async {
    final sdk = await _platformChecks.getAndroidSdkInt();
    final perms = await requiredPermissions(sdkInt: sdk);
    final statuses = await perms.request();
    final allGranted = statuses.values.every((s) => s.isGranted);
    final permanentlyDenied =
        statuses.values.any((s) => s.isPermanentlyDenied);
    final locationEnabled = await Geolocator.isLocationServiceEnabled();
    return MeshPermissionsState(
      allPermissionsGranted: allGranted,
      permanentlyDenied: permanentlyDenied,
      locationServiceEnabled: locationEnabled,
      androidSdkInt: sdk,
      statuses: statuses,
    );
  }

  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  Future<bool> openAppPermissionsSettings() => openAppSettings();
}

