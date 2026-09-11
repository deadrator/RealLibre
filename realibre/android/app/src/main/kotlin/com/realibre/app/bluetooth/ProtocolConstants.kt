package com.realibre.app.bluetooth

/**
 * Wire protocol for the Realme Buds T310 — the Oppo/Realme "HeyThings"
 * SPP protocol, reverse-engineered by the Gadgetbridge project
 * (Freeyourgadget/Gadgetbridge, AGPL — protocol details only, no code copied).
 *
 * Frame layout (all multi-byte fields LITTLE endian):
 * ```
 * [0]      preamble 0xAA
 * [1]      total length (bytes after this one, i.e. frame size - 2)
 * [2..3]   zero (0x0000; some devices use 0x0004)
 * [4..5]   command code (uint16 LE)
 * [6]      sequence number (wraps)
 * [7..8]   payload length (uint16 LE)
 * [9..N]   payload
 * ```
 *
 * There is NO CRC and NO authentication handshake on this protocol — the
 * earlier "RMV + CRC16 + HMAC" spec did not match the real firmware and the
 * buds silently ignored those frames.
 */
object ProtocolConstants {
    // Transport
    const val DEVICE_MAC: String = "88:0E:85:EF:12:24"
    const val SPP_UUID: String = "00001101-0000-1000-8000-00805F9B34FB"
    const val RFCOMM_CHANNEL: Int = 1
    const val MAX_MTU: Int = 990

    // Frame
    const val PREAMBLE: Int = 0xAA
    const val HEADER_SIZE: Int = 9 // preamble..payloadLen inclusive

    // Timeouts so a silent bud can never wedge the UI (ms).
    const val CONNECT_TIMEOUT_MS: Long = 12_000L
    const val RESPONSE_TIMEOUT_MS: Long = 4_000L

    // Command codes (uint16 LE). Requests 0x0xxx are answered by 0x8xxx RETs;
    // SET commands are answered by ACKs.
    const val CMD_BATTERY_REQ: Int = 0x0106
    const val CMD_BATTERY_RET: Int = 0x8106
    const val CMD_SUBSCRIPTION_SET: Int = 0x0205
    const val CMD_SUBSCRIPTION_ACK: Int = 0x8205
    const val CMD_SUBSCRIPTION_RET: Int = 0x0204
    const val CMD_FIRMWARE_GET: Int = 0x0105
    const val CMD_FIRMWARE_RET: Int = 0x8105
    const val CMD_TOUCH_CONFIG_REQ: Int = 0x0108
    const val CMD_TOUCH_CONFIG_RET: Int = 0x8108
    const val CMD_FIND_DEVICE_REQ: Int = 0x0400
    const val CMD_FIND_DEVICE_ACK: Int = 0x8400
    const val CMD_MISC_CONFIG_SET: Int = 0x0403
    const val CMD_MISC_CONFIG_REQ: Int = 0x010D
    const val CMD_MISC_CONFIG_ACK: Int = 0x8403
    const val CMD_MISC_CONFIG_RET: Int = 0x810D
    const val CMD_ANC_CONFIG_SET: Int = 0x0404
    const val CMD_ANC_CONFIG_REQ: Int = 0x010C
    const val CMD_ANC_CONFIG_ACK: Int = 0x8404
    const val CMD_ANC_CONFIG_RET: Int = 0x810C

    // ANC config types (first payload byte of ANC_CONFIG_*)
    const val ANC_TYPE_MODE: Int = 0x01
    const val ANC_TYPE_TOUCH_CYCLE_MODES: Int = 0x02

    // ANC mode values (MODE). NOTE: not 0/1/2 — 0x01=off, 0x02=transparency, 0x08=ANC.
    const val ANC_OFF: Int = 0x01
    const val ANC_TRANSPARENCY: Int = 0x02
    const val ANC_ON: Int = 0x08

    // Subscription types (SUBSCRIPTION_SET payload lists these)
    const val SUB_BATTERY: Int = 0x01
    const val SUB_STATUS: Int = 0x02
    const val SUB_ANC_SELECTOR: Int = 0x03
    const val SUB_GAME_MODE: Int = 0x05

    // Misc config types (MISC_CONFIG_SET payload: [type, value])
    const val MISC_GAME_MODE: Int = 0x06
    const val MISC_MULTIPOINT: Int = 0x11
}
