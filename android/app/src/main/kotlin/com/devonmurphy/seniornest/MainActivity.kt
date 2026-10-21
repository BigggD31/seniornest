package com.devonmurphy.seniornest

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Android push support: creates the high-importance channel that both
// background pushes (via the manifest default) and in-app banners use, and
// shows a banner for a push that arrives while the app is open (Firebase
// does not do that on Android). Tapping a banner reports its type back to
// Dart so the matching tab opens, same as tapping a background push.
class MainActivity : FlutterFragmentActivity() {
    private var notifyChannel: MethodChannel? = null
    private var nextId = 1000

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createAlertsChannel()
        notifyChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "seniornest/notify").also {
            it.setMethodCallHandler { call, result ->
                if (call.method == "show") {
                    showBanner(
                        call.argument<String>("title") ?: "",
                        call.argument<String>("body") ?: "",
                        call.argument<String>("type"),
                    )
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val type = intent.getStringExtra(EXTRA_TYPE) ?: return
        intent.removeExtra(EXTRA_TYPE)
        notifyChannel?.invokeMethod("tapped", type)
    }

    private fun createAlertsChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "SeniorNest alerts",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply { description = "Messages, check-ins and emergency alerts from your Nest" }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun showBanner(title: String, body: String, type: String?) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) return
        val id = nextId++
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            if (type != null) putExtra(EXTRA_TYPE, type)
        }
        val tap = PendingIntent.getActivity(
            this, id, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setColor(0xFF5DA399.toInt())
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(tap)
            .build()
        NotificationManagerCompat.from(this).notify(id, notification)
    }

    companion object {
        const val CHANNEL_ID = "seniornest_alerts"
        const val EXTRA_TYPE = "seniornest_push_type"
    }
}
