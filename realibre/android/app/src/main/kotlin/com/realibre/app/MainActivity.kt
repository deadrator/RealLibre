package com.realibre.app

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.realibre.app.bluetooth.BudStateCache
import com.realibre.app.bluetooth.ProtocolConstants
import com.realibre.app.bluetooth.RfcommManager
import com.realibre.app.pairing.DevicePairer
import com.realibre.app.service.BatteryNotificationService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Flutter ↔ native bridge. All socket traffic stays inside [RfcommManager]
 * (framed Oppo protocol); this class only orchestrates it.
 */
class MainActivity : FlutterActivity() {

    companion object {
        const val METHOD_CHANNEL = "realibre/methods"
        const val EVENT_CHANNEL = "realibre/events"
        private const val PERMISSION_REQUEST_CODE = 1001
        private const val PREFS = "realibre_prefs"
        private const val KEY_KEEP_ALIVE = "keep_alive_background"
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var sink: EventChannel.EventSink? = null
    private val collectors = mutableListOf<Job>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    sink = events
                    collectors += scope.launch {
                        RfcommManager.state.collect { s ->
                            sink?.success(mapOf("type" to "connection", "state" to s.name))
                        }
                    }
                    collectors += scope.launch {
                        RfcommManager.debug.collect { line ->
                            sink?.success(mapOf("type" to "debug", "line" to line))
                        }
                    }
                    collectors += scope.launch {
                        RfcommManager.incoming.collect { ev ->
                            when (ev) {
                                is RfcommManager.Incoming.BatteryLevel -> sink?.success(
                                    mapOf(
                                        "type" to "battery",
                                        "left" to ev.battery.left,
                                        "right" to ev.battery.right,
                                        "case" to ev.battery.case,
                                        "source" to "rfcomm",
                                        "timestamp" to System.currentTimeMillis(),
                                    ),
                                )
                                is RfcommManager.Incoming.NoiseModeChanged -> sink?.success(
                                    mapOf("type" to "noiseMode", "value" to ev.value),
                                )
                                is RfcommManager.Incoming.GameModeChanged -> sink?.success(
                                    mapOf("type" to "gameMode", "enabled" to ev.enabled),
                                )
                                is RfcommManager.Incoming.Error ->
                                    sink?.success(mapOf("type" to "error", "message" to ev.message))
                                else -> Unit
                            }
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    sink = null
                    collectors.forEach { it.cancel() }
                    collectors.clear()
                }
            },
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermissions" -> result.success(hasRequiredPermissions())

                "requestPermissions" -> {
                    requestRequiredPermissions()
                    result.success(true)
                }

                "isBonded" -> result.success(
                    // bondedDevices throws SecurityException when
                    // BLUETOOTH_CONNECT isn't granted yet (e.g. right after the
                    // permission dialog opens) — which would strand the Dart
                    // await forever. Report "not bonded" instead.
                    if (hasRequiredPermissions()) {
                        runCatching { DevicePairer.isBonded(this) }.getOrDefault(false)
                    } else {
                        false
                    },
                )

                "pair" -> scope.launch {
                    try {
                        if (!hasRequiredPermissions()) {
                            requestRequiredPermissions()
                            result.error(
                                "MISSING_PERMISSIONS",
                                "Bluetooth permission not granted yet — accept the system dialog and retry",
                                null,
                            )
                            return@launch
                        }
                        result.success(DevicePairer.ensureBonded(applicationContext))
                    } catch (e: Exception) {
                        result.error("PAIR_FAILED", e.message ?: e.javaClass.simpleName, null)
                    }
                }

                "connect" -> scope.launch {
                    try {
                        RfcommManager.connect(applicationContext)
                        result.success(true)
                    } catch (e: Exception) {
                        // Always answer, even on unexpected throwables: a
                        // missing reply is what leaves the UI spinner stuck.
                        val message = listOf(e.message, e.cause?.message)
                            .filterNotNull()
                            .joinToString(" — ")
                            .ifEmpty { e.javaClass.simpleName }
                        result.error("CONNECT_FAILED", message, null)
                    }
                }

                "disconnect" -> {
                    RfcommManager.disconnect()
                    result.success(true)
                }

                "queryBattery" -> scope.launch {
                    try {
                        val b = RfcommManager.queryBattery()
                        BudStateCache.battery.value = b
                        result.success(
                            mapOf(
                                "left" to b.left,
                                "right" to b.right,
                                "case" to b.case,
                                "source" to "rfcomm",
                            ),
                        )
                    } catch (e: Exception) {
                        result.error("BATTERY_FAILED", e.message, null)
                    }
                }

                "setNoiseMode" -> {
                    val value = (call.argument<Number>("value") ?: 0).toInt()
                    scope.launch {
                        try {
                            RfcommManager.setNoiseMode(value)
                            BudStateCache.noiseMode.value = value
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("NOISE_FAILED", e.message, null)
                        }
                    }
                }

                "setGameMode" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    scope.launch {
                        try {
                            RfcommManager.setGameMode(enabled)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("GAME_FAILED", e.message, null)
                        }
                    }
                }

                "setMultipoint" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    scope.launch {
                        try {
                            RfcommManager.setMultipoint(enabled)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("MULTIPOINT_FAILED", e.message, null)
                        }
                    }
                }

                "setAncCycleMode" -> {
                    val value = (call.argument<Number>("value") ?: 0).toInt()
                    scope.launch {
                        try {
                            RfcommManager.setAncCycleMode(value)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ANC_CYCLE_FAILED", e.message, null)
                        }
                    }
                }

                "setMiscConfig" -> {
                    val type = (call.argument<Number>("type") ?: 0).toInt()
                    val value = (call.argument<Number>("value") ?: 0).toInt()
                    scope.launch {
                        try {
                            RfcommManager.setMiscConfig(type, value)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("MISC_FAILED", e.message, null)
                        }
                    }
                }

                "triggerFitSweep" -> scope.launch {
                    try {
                        RfcommManager.triggerFitSweep()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("FIT_FAILED", e.message, null)
                    }
                }

                "findDevice" -> scope.launch {
                    try {
                        RfcommManager.findDevice(true)
                        kotlinx.coroutines.delay(3000)
                        RfcommManager.findDevice(false)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("FIND_FAILED", e.message, null)
                    }
                }

                "triggerBatteryPopup" -> scope.launch {
                    try {
                        val b = fetchAndCacheBattery()
                        result.success(DevicePairer.firePreciseBatteryBroadcast(applicationContext, b))
                    } catch (e: Exception) {
                        result.error("POPUP_FAILED", e.message, null)
                    }
                }

                "startBatteryService" -> {
                    BatteryNotificationService.start(this)
                    result.success(true)
                }

                "getKeepAlive" -> result.success(
                    getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_KEEP_ALIVE, true),
                )

                "setKeepAlive" -> {
                    val value = call.arguments as? Boolean ?: true
                    getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                        .edit().putBoolean(KEY_KEEP_ALIVE, value).apply()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    private suspend fun fetchAndCacheBattery(): RfcommManager.Battery {
        val b = RfcommManager.queryBattery()
        BudStateCache.battery.value = b
        return b
    }

    /** Honor the Keep alive in background setting: drop the socket when hidden. */
    override fun onPause() {
        super.onPause()
        val keepAlive = getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_KEEP_ALIVE, true)
        if (!keepAlive && RfcommManager.isConnected) RfcommManager.disconnect()
    }

    private fun hasRequiredPermissions(): Boolean {
        val needed = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= 31) {
            needed += Manifest.permission.BLUETOOTH_CONNECT
            needed += Manifest.permission.BLUETOOTH_SCAN
        }
        if (Build.VERSION.SDK_INT >= 33) needed += Manifest.permission.POST_NOTIFICATIONS
        return needed.all { ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED }
    }

    private fun requestRequiredPermissions() {
        val needed = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= 31) {
            needed += Manifest.permission.BLUETOOTH_CONNECT
            needed += Manifest.permission.BLUETOOTH_SCAN
        }
        if (Build.VERSION.SDK_INT >= 33) needed += Manifest.permission.POST_NOTIFICATIONS
        if (needed.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, needed.toTypedArray(), PERMISSION_REQUEST_CODE)
        }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
