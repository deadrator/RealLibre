package com.realibre.app.service

import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.realibre.app.bluetooth.BudStateCache

/**
 * Listens for Fast Pair's coarse battery broadcast as a secondary signal when
 * RFCOMM is unavailable, and for bond state transitions.
 */
class BluetoothStateReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            "com.google.android.gms.nearby.discovery.ACTION_BATTERY_CHANGED" -> {
                val left = intent.getIntExtra("battery_left", -1)
                val right = intent.getIntExtra("battery_right", -1)
                val case = intent.getIntExtra("battery_case", -1)
                if (left >= 0 || right >= 0 || case >= 0) {
                    val current = BudStateCache.battery.value
                    BudStateCache.battery.value = com.realibre.app.bluetooth.RfcommManager.Battery(
                        left = if (left in 0..100) left else current?.left ?: 0,
                        right = if (right in 0..100) right else current?.right ?: 0,
                        case = if (case in 0..100) case else current?.case ?: 0,
                    )
                }
            }
            android.bluetooth.BluetoothDevice.ACTION_BOND_STATE_CHANGED -> {
                val device: BluetoothDevice? =
                    intent.getParcelableExtra(android.bluetooth.BluetoothDevice.EXTRA_DEVICE)
                if (device?.address?.equals("88:0E:85:EF:12:24", ignoreCase = true) == true) {
                    // Bond resolved; MainActivity's connect() handles the rest.
                }
            }
        }
    }
}
