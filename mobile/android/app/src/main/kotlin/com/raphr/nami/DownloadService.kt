package com.raphr.nami

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.Process

/**
 * Keeps the process alive while a download runs: the torrent engine lives in
 * it. All the work is in the engine and in Dart.
 */
class DownloadService : Service() {
    companion object {
        private const val CHANNEL = "downloads"
        private const val ID = 1

        var running = false
            private set

        fun update(context: Context, title: String, text: String, percent: Int) {
            if (running) {
                context.getSystemService(NotificationManager::class.java)
                    .notify(ID, build(context, title, text, percent))
                return
            }
            val intent = Intent(context, DownloadService::class.java)
                .putExtra("title", title).putExtra("text", text).putExtra("percent", percent)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, DownloadService::class.java))
        }

        private fun build(context: Context, title: String, text: String, percent: Int): Notification {
            val open = PendingIntent.getActivity(
                context, 0, Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.getSystemService(NotificationManager::class.java).createNotificationChannel(
                    NotificationChannel(CHANNEL, "Downloads", NotificationManager.IMPORTANCE_LOW),
                )
                Notification.Builder(context, CHANNEL)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }
            return builder
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setContentTitle(title)
                .setContentText(text)
                .setProgress(100, percent, false)
                .setContentIntent(open)
                .setOngoing(true)
                .build()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = build(
            this,
            intent?.getStringExtra("title") ?: "Nami",
            intent?.getStringExtra("text") ?: "",
            intent?.getIntExtra("percent", 0) ?: 0,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(ID, notification)
        }
        running = true
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    // Swiped away: the app restarts clean and resumes the queue from what it saved.
    override fun onTaskRemoved(rootIntent: Intent?) {
        stopSelf()
        Process.killProcess(Process.myPid())
    }
}
