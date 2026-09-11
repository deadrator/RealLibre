package com.realibre.app.bluetooth

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/**
 * Golden-vector tests for the framing layer. Run with:
 * `cd android && ./gradlew :app:testDebugUnitTest`
 */
class ProtocolTest {

    @Test
    fun `crc16 matches XMODEM golden vector for ASCII 123456789`() {
        // CRC-16/XMODEM (poly 0x1021, init 0, no reflect, no xorout) of "123456789"
        val data = "123456789".toByteArray(Charsets.US_ASCII)
        assertEquals(0x31C3, Crc16.compute(data) and 0xFFFF)
    }

    @Test
    fun `crc16 of empty input is initial value`() {
        assertEquals(0x0000, Crc16.compute(ByteArray(0)))
    }

    @Test
    fun `crc16 is stable across repeated invocations`() {
        val data = byteArrayOf(0x52, 0x4D, 0x56, 0x04, 0x01, 0x00, 0x03, 0x02, 0x05, 0x01)
        val first = Crc16.compute(data)
        val second = Crc16.compute(data.copyOf())
        assertEquals(first, second)
        assertTrue(first in 0..0xFFFF)
    }

    @Test
    fun `frame build then parse round-trips payload`() {
        val payload = byteArrayOf(0x02, 0x05, 0x01) // ATTR_SET noise=ANC
        val frame = FrameBuilder.build(ProtocolConstants.CMD_ATTR_SET, 0x07, payload)

        // Header checks
        assertEquals(0x52, frame[0].toInt() and 0xFF)
        assertEquals(0x4D, frame[1].toInt() and 0xFF)
        assertEquals(0x56, frame[2].toInt() and 0xFF)
        assertEquals(ProtocolConstants.CMD_ATTR_SET, frame[3].toInt() and 0xFF)
        assertEquals(0x07, frame[4].toInt() and 0xFF)
        assertEquals(0x00, frame[5].toInt() and 0xFF) // length hi
        assertEquals(0x03, frame[6].toInt() and 0xFF) // length lo

        val parsed = FrameBuilder.parse(frame)
        assertEquals(ProtocolConstants.CMD_ATTR_SET, parsed.command)
        assertEquals(0x07, parsed.sequence)
        assertTrue(payload.contentEquals(parsed.payload))
    }

    @Test
    fun `parse rejects corrupted payload via CRC mismatch`() {
        val payload = byteArrayOf(0x02, 0x05, 0x01)
        val frame = FrameBuilder.build(ProtocolConstants.CMD_ATTR_SET, 1, payload)
        frame[frame.size - 3] = (frame[frame.size - 3].toInt() xor 0x40).toByte() // corrupt payload byte
        assertFailsWith<FrameBuilder.FrameException> { FrameBuilder.parse(frame) }
    }

    @Test
    fun `parse rejects wrong magic`() {
        val bad = byteArrayOf(0x00, 0x4D, 0x56, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00)
        assertFailsWith<FrameBuilder.FrameException> { FrameBuilder.parse(bad) }
    }

    @Test
    fun `parse rejects truncated frame`() {
        val frame = FrameBuilder.build(ProtocolConstants.CMD_STATUS_QUERY, 2, byteArrayOf(0x11, 0x22))
        val truncated = frame.copyOfRange(0, frame.size - 1)
        assertFailsWith<FrameBuilder.FrameException> { FrameBuilder.parse(truncated) }
    }

    @Test
    fun `sequence wraps within byte range`() {
        val frame = FrameBuilder.build(0x03, 0xFF)
        assertEquals(0xFF, FrameBuilder.parse(frame).sequence)
    }

    @Test
    fun `hmac response payload layout is 0x0A plus 32-byte signature`() {
        val earbudRandom = ByteArray(16) { it.toByte() }
        val payload = HmacAuth.buildResponsePayload(earbudRandom)
        assertEquals(1 + 32, payload.size)
        assertEquals(0x0A, payload[0].toInt() and 0xFF)
    }

    @Test
    fun `auth challenge reply parses earbud random on valid signature`() {
        val clientRandom = ByteArray(16) { (it * 3).toByte() }
        val earbudRandom = ByteArray(16) { (it * 7).toByte() }
        val sig = HmacAuth.sign(clientRandom)
        val replyPayload = ByteArray(1 + 32 + 16)
        replyPayload[0] = 0x00
        sig.copyInto(replyPayload, 1)
        earbudRandom.copyInto(replyPayload, 33)

        val parsed = HmacAuth.verifyChallengeReply(replyPayload, clientRandom)
        assertTrue(earbudRandom.contentEquals(parsed))
    }

    @Test
    fun `auth challenge reply rejects bad signature`() {
        val clientRandom = ByteArray(16)
        val replyPayload = ByteArray(49)
        replyPayload[0] = 0x00
        HmacAuth.sign(ByteArray(16) { 0x55 }).copyInto(replyPayload, 1) // signature of wrong message
        assertFailsWith<HmacAuth.AuthException> { HmacAuth.verifyChallengeReply(replyPayload, clientRandom) }
    }
}
