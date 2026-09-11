package com.realibre.app.pairing

import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.os.Build
import com.realibre.app.bluetooth.ProtocolConstants
import com.realibre.app.bluetooth.RfcommManager

/**
 * Discovery + bonding for the Buds T310, plus the precise battery broadcast
 * used by the Fast Pair popup trigger.
 */
@SuppressLint("MissingPermission")
object DevicePairer {

    /** True when [ProtocolConstants.DEVICE_MAC] already has a bond link key. */
    fun isBonded(context: Context): Boolean {
        val adapter = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
            ?: return false
        if (!adapter.isEnabled) return false
        return adapter.bondedDevices.any { it.address.equals(ProtocolConstants.DEVICE_MAC, ignoreCase = true) }
    }

    /**
     * Ensure the buds are bonded, creating the bond if needed.
     * Uses the system bond flow (dialog) via [android.bluetooth.BluetoothDevice.createBond].
     */
    suspend fun ensureBonded(context: Context): Boolean {
        val adapter = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
            ?: throw IllegalStateException("no bluetooth adapter")
        if (!adapter.isEnabled) throw IllegalStateException("bluetooth is off")
        val device = adapter.getRemoteDevice(ProtocolConstants.DEVICE_MAC)
        if (device.bondState == android.bluetooth.BluetoothDevice.BOND_BONDED) return true

        if (Build.VERSION.SDK_INT >= 19) {
            device.createBond()
        } else {
            @Suppress("DEPRECATION")
            device.javaClass
                .getMethod("createBond")
                .invoke(device)
        }
        // Bonding completes asynchronously; poll bondState until resolved.
        var waited = 0L
        while (device.bondState == android.bluetooth.BluetoothDevice.BOND_BONDING && waited < 30_000) {
            kotlinx.coroutines.delay(300)
            waited += 300
        }
        return device.bondState == android.bluetooth.BluetoothDevice.BOND_BONDED
    }

    /**
     * Fire the Google Fast Pair battery broadcast with true 1% values from
     * Cmd 0x03 so any system/listener popup shows exact numbers.
     *
     * NOTE (README-documented limitation): GMS does not allow third-party apps
     * to force the Fast Pair UI to redraw directly on all OEM builds. Where the
     * popup cannot be triggered, this broadcast still carries precise values
     * and RealiBre's own notification reflects them 1:1 — no silent 10% rounding.
     */
    fun firePreciseBatteryBroadcast(context: Context, battery: RfcommManager.Battery): Boolean {
        return try {
            val intent = Intent("com.google.android.gms.nearby.discovery.ACTION_BATTERY_CHANGED").apply {
                putExtra("android.bluetooth.device.extra.DEVICE", macToDevice(context))
                putExtra("model_id", 0x891148)
                putExtra("battery_left", battery.left)
                putExtra("battery_right", battery.right)
                putExtra("battery_case", battery.case)
                putExtra("is_charging", false)
                setPackage("com.google.android.gms")
            }
            context.sendBroadcast(intent)
            true
        } catch (_: Exception) {
            // GMS may block implicit broadcasts to its package on newer Android.
            false
        }
    }

    private fun macToDevice(context: Context): android.bluetooth.BluetoothDevice? {
        val adapter = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
            ?: return null
        return try {
            adapter.getRemoteDevice(ProtocolConstants.DEVICE_MAC)
        } catch (_: IllegalArgumentException) {
            null
        }
    }
}
