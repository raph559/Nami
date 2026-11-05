package com.raphr.nami

import android.Manifest
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Rational
import androidx.lifecycle.Lifecycle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private companion object {
        const val TOGGLE_PAUSE = "com.raphr.nami.TOGGLE_PAUSE"
    }

    private var pip: MethodChannel? = null
    private var playing = true
    private var autoPip = false

    private val pauseButton = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            pip?.invokeMethod("togglePause", null)
        }
    }

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
        pip = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nami/pip").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "enter" -> {
                        enterPip()
                        result.success(null)
                    }
                    "playing" -> {
                        playing = call.arguments as Boolean
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && isInPictureInPictureMode) {
                            setPictureInPictureParams(pipParams())
                        }
                        result.success(null)
                    }
                    "auto" -> {
                        autoPip = call.arguments as Boolean
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onStart() {
        super.onStart()
        val filter = IntentFilter(TOGGLE_PAUSE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(pauseButton, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(pauseButton, filter)
        }
    }

    override fun onStop() {
        unregisterReceiver(pauseButton)
        super.onStop()
    }

    private fun pipParams(): PictureInPictureParams {
        val icon = if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
        val label = if (playing) "Pause" else "Play"
        val press = PendingIntent.getBroadcast(
            this, 0, Intent(TOGGLE_PAUSE).setPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
            .setActions(listOf(RemoteAction(Icon.createWithResource(this, icon), label, label, press)))
            .build()
    }

    private fun enterPip() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) enterPictureInPictureMode(pipParams())
    }

    // Home while a video plays shrinks it instead of stopping it.
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (autoPip) enterPip()
    }

    override fun onPictureInPictureModeChanged(active: Boolean, config: Configuration) {
        super.onPictureInPictureModeChanged(active, config)
        // Closed with the window's X: the activity stopped instead of coming back.
        val closed = !active && !lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)
        pip?.invokeMethod("changed", mapOf("active" to active, "closed" to closed))
    }

    // Leaving with a download running only goes to the background, so it goes on.
    override fun finish() {
        if (DownloadService.running) moveTaskToBack(true) else super.finish()
    }
}
