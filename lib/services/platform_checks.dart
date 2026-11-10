import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PlayServicesStatus {
  final bool isAvailable;
  final int statusCode;
  final String statusMessage;

  const PlayServicesStatus({
    required this.isAvailable,
    required this.statusCode,
    required this.statusMessage,
  });
}

class PlatformChecks {
  static const MethodChannel _channel =
      MethodChannel('com.meshrescue.mesh_rescue/platform');

  Future<int> getAndroidSdkInt() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return 0;
    }
    try {
      final result = await _channel.invokeMethod<int>('getSdkInt');
      return result ?? 0;
    } on PlatformException {
      return 0;
    } on MissingPluginException {
      return 0;
    }
  }

  Future<PlayServicesStatus> checkGooglePlayServices() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const PlayServicesStatus(
        isAvailable: false,
        statusCode: -1,
        statusMessage: 'MeshRescue requires an Android device with Google Play Services.',
      );
    }
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'checkPlayServices',
      );
      final available = res?['available'] as bool? ?? false;
      final code = res?['statusCode'] as int? ?? -1;
      final msg = res?['statusMessage'] as String? ?? 'Unknown status';
      return PlayServicesStatus(
        isAvailable: available,
        statusCode: code,
        statusMessage: msg,
      );
    } on PlatformException catch (e) {
      return PlayServicesStatus(
        isAvailable: false,
        statusCode: -1,
        statusMessage: e.message ?? 'Play Services check failed',
      );
    } on MissingPluginException {
      return const PlayServicesStatus(
        isAvailable: false,
        statusCode: -1,
        statusMessage: 'Platform channel unavailable',
      );
    }
  }
}

