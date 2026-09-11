package com.realibre.app.bluetooth

import kotlinx.coroutines.flow.MutableStateFlow

/**
 * Shared in-process cache so the QS tile, notification service and the Flutter
 * UI all agree on bud state without opening extra sockets (max-1-connection).
 */
object BudStateCache {
    /** Attr 0x05 value: 0x00 Off, 0x01 ANC, 0x02 Transparency. Null = unknown. */
    val noiseMode = MutableStateFlow<Int?>(null)

    /** Latest Cmd 0x03 telemetry. */
    val battery = MutableStateFlow<RfcommManager.Battery?>(null)
}
