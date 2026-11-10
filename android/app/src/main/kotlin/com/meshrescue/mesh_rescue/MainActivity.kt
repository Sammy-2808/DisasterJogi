package com.meshrescue.mesh_rescue

import android.os.Build
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.meshrescue.mesh_rescue/platform"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSdkInt" -> result.success(Build.VERSION.SDK_INT)
                    "checkPlayServices" -> {
                        val availability = GoogleApiAvailability.getInstance()
                        val code = availability.isGooglePlayServicesAvailable(this)
                        result.success(
                            mapOf(
                                "available" to (code == ConnectionResult.SUCCESS),
                                "statusCode" to code,
                                "statusMessage" to availability.getErrorString(code),
                            )
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
