package com.realibre.app.service

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.realibre.app.MainActivity
import com.realibre.app.R
import com.realibre.app.bluetooth.BudStateCache
import com.realibre.app.bluetooth.ProtocolConstants
import com.realibre.app.bluetooth.RfcommManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Persistent, low-priority foreground notification showing L/R/Case % from the
 * last Cmd 0x03 poll, with a quick ANC-cycle action button.
 */
class BatteryNotificationService : Service() {

    companion object {
        const val CHANNEL_ID = "realibre_battery"
        const val NOTIFICATION_ID = 42
        const val ACTION_CYCLE_ANC = "com.realibre.app.action.CYCLE_ANC"
        const val ACTION_REFRESH = "com.realibre.app.action.REFRESH_BATTERY"

        fun start(context: Context) {
            val intent = Intent(context, BatteryNotificationService::class.java)
            androidx.core.content.ContextCompat.startForegroundService(context, intent)
        }
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        startForeground(NOTIFICATION_ID, buildNotification(null))
        scope.launch {
            BudStateCache.battery.collect { b ->
                val nm = getSystemService(NotificationManager::class.java)
                nm.notify(NOTIFICATION_ID, buildNotification(b))
            }
        }
        scope.launch { refreshOnce() }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CYCLE_ANC -> {
                scope.launch {
                    val next = cycleNoiseMode(BudStateCache.noiseMode.value)
                    runCatching { RfcommManager.setAttribute(ProtocolConstants.ATTR_NOISE_CONTROL, next) }
                    BudStateCache.noiseMode.value = next
                }
            }
            ACTION_REFRESH -> scope.launch { refreshOnce() }
            null -> Unit
        }
        return START_STICKY
    }

    private suspend fun refreshOnce() {
        runCatching {
            if (RfcommManager.isConnected) {
                BudStateCache.battery.value = RfcommManager.queryBattery()
            }
        }
    }

    private fun cycleNoiseMode(current: Int?): Int = when (current) {
        ProtocolConstants.NOISE_ANC -> ProtocolConstants.NOISE_TRANSPARENCY
        ProtocolConstants.NOISE_TRANSPARENCY -> ProtocolConstants.NOISE_OFF
        else -> ProtocolConstants.NOISE_ANC
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Battery status",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Realme Buds T310 battery level"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    @SuppressLint("MissingPermission")
    private fun buildNotification(battery: RfcommManager.Battery?): Notification {
        val openApp = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val cycleAnc = PendingIntent.getService(
            this, 1, Intent(this, BatteryNotificationService::class.java).setAction(ACTION_CYCLE_ANC),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val text = battery?.let { "L ${it.left}%  •  R ${it.right}%  •  Case ${it.case}%" } ?: "Tap refresh to poll buds"
        val title = when (BudStateCache.noiseMode.value) {
            ProtocolConstants.NOISE_ANC -> "ANC on"
            ProtocolConstants.NOISE_TRANSPARENCY -> "Transparency"
            ProtocolConstants.NOISE_OFF -> "Noise off"
            else -> "RealiBre"
        }

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_buds)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setContentIntent(openApp)
            .addAction(0, "Cycle ANC", cycleAnc)
            .setOnlyAlertOnce(true)
        return builder.build()
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
