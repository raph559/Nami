package com.raphr.nami

import android.Manifest
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nami/downloads").setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    DownloadService.update(
                        this,
                        call.argument<String>("title") ?: "Nami",
                        call.argument<String>("text") ?: "",
                        call.argument<Int>("percent") ?: 0,
                    )
                    result.success(null)
                }
                "stop" -> {
                    DownloadService.stop(this)
                    result.success(null)
                }
                "askPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // Leaving with a download running only goes to the background, so it goes on.
    override fun finish() {
        if (DownloadService.running) moveTaskToBack(true) else super.finish()
    }
}
