package com.realibre.app.bluetooth

/**
 * Bitwise CRC-16 with initial value 0 and XOR-masked shifts, as used by the
 * Realme Buds T310 framing layer. Kept dependency-free so it can be unit
 * tested in isolation before being trusted by [FrameBuilder].
 *
 * Algorithm (per spec):
 *  - initial value: 0x0000
 *  - MSB-first: for each byte, XOR into the high byte of the register
 *  - 8 shifts per byte; each shift XORs the polynomial with the register when
 *    the shifted-out MSB was 1 (XOR-masked shifts)
 *  - polynomial: 0x1021 (CRC-16/CCITT-FALSE family, but with init 0x0000)
 */
object Crc16 {

    /** Polynomial used for the XOR-masked shift register. */
    const val POLYNOMIAL: Int = 0x1021

    /** Initial register value. */
    const val INITIAL: Int = 0x0000

    /** Compute the CRC-16 of [data]. */
    fun compute(data: ByteArray): Int = compute(data, 0, data.size)

    /** Compute the CRC-16 of [data] over [from] until (exclusive) [to]. */
    fun compute(data: ByteArray, from: Int = 0, to: Int = data.size): Int {
        var crc = INITIAL
        for (i in from until to) {
            crc = crc xor ((data[i].toInt() and 0xFF) shl 8)
            repeat(8) {
                crc = if (crc and 0x8000 != 0) {
                    (crc shl 1) xor POLYNOMIAL
                } else {
                    crc shl 1
                }
                crc = crc and 0xFFFF
            }
        }
        return crc
    }

    /** Pack a CRC value as uint16 big endian. */
    fun toBytes(crc: Int): ByteArray = byteArrayOf(
        ((crc ushr 8) and 0xFF).toByte(),
        (crc and 0xFF).toByte(),
    )

    /** Read a uint16 big-endian CRC from [data] at [offset]. */
    fun fromBytes(data: ByteArray, offset: Int): Int =
        ((data[offset].toInt() and 0xFF) shl 8) or (data[offset + 1].toInt() and 0xFF)
}
