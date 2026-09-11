package com.realibre.app.bluetooth

/**
 * Single source of truth for the wire protocol spoken by the Realme Buds T310.
 *
 * Every command is framed as:
 * ```
 * [0..2]  magic "RMV" (0x52 0x4D 0x56)
 * [3]     command type
 * [4]     sequence number (wraps 0x00-0xFF)
 * [5..6]  payload length, uint16 big endian
 * [7..N]  payload
 * [N+1..N+2] CRC16, uint16 big endian
 * ```
 */
object ProtocolConstants {
    // Transport
    const val DEVICE_MAC: String = "88:0E:85:EF:12:24"
    const val SPP_UUID: String = "00001101-0000-1000-8000-00805F9B34FB"
    const val RFCOMM_CHANNEL: Int = 1
    const val MAX_MTU: Int = 990

    // [0..2] magic header "RMV"
    val MAGIC: ByteArray = byteArrayOf(0x52, 0x4D, 0x56)

    // Frame offsets
    const val OFFSET_MAGIC: Int = 0
    const val OFFSET_COMMAND: Int = 3
    const val OFFSET_SEQUENCE: Int = 4
    const val OFFSET_LENGTH: Int = 5
    const val OFFSET_PAYLOAD: Int = 7
    const val HEADER_SIZE: Int = 7
    const val CRC_SIZE: Int = 2

    // Command types
    const val CMD_AUTH_CHALLENGE: Int = 0x01
    const val CMD_AUTH_RESPONSE: Int = 0x02
    const val CMD_STATUS_QUERY: Int = 0x03
    const val CMD_ATTR_SET: Int = 0x04

    // Auth handshake sizes
    const val CHALLENGE_SIZE: Int = 16
    const val HMAC_SIZE: Int = 32
    const val AUTH_STATUS_OFFSET: Int = 0
    const val AUTH_SIG_OFFSET: Int = 1
    const val AUTH_EARBUD_RANDOM_OFFSET: Int = 33

    // Shared secret (per spec) used as HMAC-SHA256 key.
    val HMAC_KEY: ByteArray = "hmac_key".toByteArray(Charsets.UTF_8)

    // Cmd 0x04 payload layout: [Length=0x02, Attr_ID, Value]
    const val ATTR_PAYLOAD_LENGTH: Int = 0x02

    // Attribute IDs (Cmd 0x04)
    const val ATTR_NOISE_CONTROL: Int = 0x05
    const val ATTR_ANC_SUB_LEVEL: Int = 0x14
    const val ATTR_GAMING: Int = 0x06
    const val ATTR_SPATIAL_AUDIO: Int = 0x10
    const val ATTR_EQ_MODE: Int = 0x0A
    const val ATTR_VOLUME_ENHANCER: Int = 0x0E
    const val ATTR_WIND_NOISE: Int = 0x12
    const val ATTR_ENHANCE_VOICES: Int = 0x13
    const val ATTR_MULTIPOINT: Int = 0x09
    const val ATTR_FIT_TEST: Int = 0x15

    // Noise control values (Attr 0x05)
    const val NOISE_OFF: Int = 0x00
    const val NOISE_ANC: Int = 0x01
    const val NOISE_TRANSPARENCY: Int = 0x02

    // ANC sub-level values (Attr 0x14)
    const val ANC_LEVEL_MILD: Int = 0x00
    const val ANC_LEVEL_MODERATE: Int = 0x01
    const val ANC_LEVEL_DEEP: Int = 0x02

    // EQ mode values (Attr 0x0A)
    const val EQ_DEFAULT: Int = 0x00
    const val EQ_BASS_BOOST: Int = 0x01
    const val EQ_CLEAR_BASS: Int = 0x02
    const val EQ_CLEAR_VOCALS: Int = 0x03

    // Battery indices for Cmd 0x03 status payload
    const val BATTERY_LEFT: Int = 0
    const val BATTERY_RIGHT: Int = 1
    const val BATTERY_CASE: Int = 2

    // Timeouts so a silent bud can never wedge the UI (ms).
    const val CONNECT_TIMEOUT_MS: Long = 12_000L
    const val HANDSHAKE_TIMEOUT_MS: Long = 8_000L
}
