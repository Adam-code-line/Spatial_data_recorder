package com.binwu.reconstruction.spatial_data_recorder

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.binwu.reconstruction.spatial_data_recorder/recorder",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getRecordingStatus" -> result.success(
                    mapOf<String, Any?>(
                        "recording" to false,
                        "activeSessionPath" to null,
                        "lastCompletedSessionPath" to null,
                    ),
                )
                "startRecording", "stopRecording" -> result.error(
                    "android_not_implemented",
                    "P0 采集仅在 iOS 实现；Android 后续再接入。",
                    null,
                )
                else -> result.notImplemented()
            }
        }
    }
}
