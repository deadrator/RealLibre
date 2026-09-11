package com.realibre.app.service

import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.realibre.app.bluetooth.BudStateCache
import com.realibre.app.bluetooth.ProtocolConstants
import com.realibre.app.bluetooth.RfcommManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Quick Settings tile cycling ANC → Transparency → Off through the same
 * authenticated RfcommManager path as the in-app selector (max-1-connection:
 * it shares the single socket, never opens a second one).
 */
class NoiseControlTileService : TileService() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    override fun onStartListening() {
        super.onStartListening()
        updateTile(BudStateCache.noiseMode.value)
        // Opportunistic reconnect; a tap while disconnected shows a toast instead of failing silently.
        scope.launch {
            if (!RfcommManager.isConnected) {
                runCatching { RfcommManager.connect(applicationContext) }
                    .onSuccess { refreshMode() }
                    .onFailure {
                        android.widget.Toast.makeText(
                            this@NoiseControlTileService,
                            "RealiBre: buds not connected",
                            android.widget.Toast.LENGTH_SHORT,
                        ).show()
                    }
            }
        }
    }

    override fun onStopListening() {
        super.onStopListening()
    }

    override fun onClick() {
        super.onClick()
        val current = BudStateCache.noiseMode.value
        val next = when (current) {
            ProtocolConstants.NOISE_ANC -> ProtocolConstants.NOISE_TRANSPARENCY
            ProtocolConstants.NOISE_TRANSPARENCY -> ProtocolConstants.NOISE_OFF
            else -> ProtocolConstants.NOISE_ANC
        }
        updateTile(next) // optimistic
        scope.launch {
            try {
                if (!RfcommManager.isConnected) {
                    RfcommManager.connect(applicationContext)
                }
                RfcommManager.setAttribute(ProtocolConstants.ATTR_NOISE_CONTROL, next)
                BudStateCache.noiseMode.value = next
                updateTile(next)
            } catch (e: Exception) {
                updateTile(BudStateCache.noiseMode.value)
                android.widget.Toast.makeText(
                    this@NoiseControlTileService,
                    "RealiBre: ${e.message}",
                    android.widget.Toast.LENGTH_SHORT,
                ).show()
            }
        }
    }

    private suspend fun refreshMode() {
        // The protocol has no read-back for Attr 0x05 here; keep last known.
        updateTile(BudStateCache.noiseMode.value)
    }

    private fun updateTile(mode: Int?) {
        val tile = qsTile ?: return
        val subtitle: String?
        when (mode) {
            ProtocolConstants.NOISE_ANC -> {
                tile.state = Tile.STATE_ACTIVE
                tile.label = "ANC"
                subtitle = "Noise cancelling"
            }
            ProtocolConstants.NOISE_TRANSPARENCY -> {
                tile.state = Tile.STATE_ACTIVE
                tile.label = "Transparency"
                subtitle = "Hear surroundings"
            }
            ProtocolConstants.NOISE_OFF -> {
                tile.state = Tile.STATE_INACTIVE
                tile.label = "Noise off"
                subtitle = "No cancellation"
            }
            else -> {
                tile.state = Tile.STATE_UNAVAILABLE
                tile.label = "RealiBre"
                subtitle = "Not connected"
            }
        }
        // Tile.subtitle is API 29+; minSdk is 26.
        if (android.os.Build.VERSION.SDK_INT >= 29) {
            tile.subtitle = subtitle ?: ""
        }
        tile.updateTile()
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
