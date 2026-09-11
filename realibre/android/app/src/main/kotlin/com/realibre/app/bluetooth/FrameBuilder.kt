package com.realibre.app.bluetooth

import java.io.ByteArrayOutputStream
import java.io.EOFException
import java.io.IOException
import java.nio.ByteBuffer

/** Hex dump helper for wire logging (capped so logcat stays readable). */
fun ByteArray.toHexString(limit: Int = 64): String = buildString {
    append('[')
    for (i in 0 until minOf(size, limit)) {
        if (i > 0) append(' ')
        append((this@toHexString[i].toInt() and 0xFF).toString(16).padStart(2, '0'))
    }
    if (size > limit) append(" …(+${size - limit})")
    append(']')
}

/**
 * Assembles and parses "RMV" frames:
 *
 * ```
 * [0..2]      magic 0x52 0x4D 0x56 ("RMV")
 * [3]         command type
 * [4]         sequence number
 * [5..6]      payload length (uint16 BE)
 * [7..N]      payload
 * [N+1..N+2]  CRC16 (uint16 BE) over bytes [0..N]
 * ```
 *
 * CRC covers the header (magic + command + sequence + length) and the payload,
 * not the CRC bytes themselves.
 */
object FrameBuilder {

    /** Immutable decoded view of one frame. */
    data class Frame(
        val command: Int,
        val sequence: Int,
        val payload: ByteArray,
    ) {
        override fun equals(other: Any?): Boolean =
            other is Frame && command == other.command && sequence == other.sequence && payload.contentEquals(other.payload)

        override fun hashCode(): Int = 31 * (31 * command + sequence) + payload.contentHashCode()
    }

    /** Thrown when a received buffer is not a valid frame. */
    class FrameException(message: String) : IOException(message)

    private val MAGIC: ByteArray = ProtocolConstants.MAGIC

    /** Build a complete framed packet ready to write to the RFCOMM socket. */
    fun build(command: Int, sequence: Int, payload: ByteArray = ByteArray(0)): ByteArray {
        require(command in 0..0xFF) { "command out of range" }
        require(sequence in 0..0xFF) { "sequence out of range" }
        require(payload.size <= ProtocolConstants.MAX_MTU - ProtocolConstants.HEADER_SIZE - ProtocolConstants.CRC_SIZE) {
            "payload exceeds MTU budget"
        }

        val length = payload.size
        val frame = ByteArray(ProtocolConstants.HEADER_SIZE + length + ProtocolConstants.CRC_SIZE)
        MAGIC.copyInto(frame, ProtocolConstants.OFFSET_MAGIC)
        frame[ProtocolConstants.OFFSET_COMMAND] = command.toByte()
        frame[ProtocolConstants.OFFSET_SEQUENCE] = sequence.toByte()
        frame[ProtocolConstants.OFFSET_LENGTH] = ((length ushr 8) and 0xFF).toByte()
        frame[ProtocolConstants.OFFSET_LENGTH + 1] = (length and 0xFF).toByte()
        payload.copyInto(frame, ProtocolConstants.OFFSET_PAYLOAD)

        val crc = Crc16.compute(frame, 0, ProtocolConstants.HEADER_SIZE + length)
        frame[frame.size - 2] = ((crc ushr 8) and 0xFF).toByte()
        frame[frame.size - 1] = (crc and 0xFF).toByte()
        return frame
    }

    /**
     * Validate and decode a single complete frame from [data].
     * [data] must contain exactly one frame (no trailing bytes).
     */
    fun parse(data: ByteArray): Frame {
        if (data.size < ProtocolConstants.HEADER_SIZE + ProtocolConstants.CRC_SIZE) {
            throw FrameException("frame too short (${data.size} bytes)")
        }
        for (i in MAGIC.indices) {
            if (data[i] != MAGIC[i]) throw FrameException("bad magic at byte $i")
        }
        val command = data[ProtocolConstants.OFFSET_COMMAND].toInt() and 0xFF
        val sequence = data[ProtocolConstants.OFFSET_SEQUENCE].toInt() and 0xFF
        val length = ((data[ProtocolConstants.OFFSET_LENGTH].toInt() and 0xFF) shl 8) or
            (data[ProtocolConstants.OFFSET_LENGTH + 1].toInt() and 0xFF)

        val expected = ProtocolConstants.HEADER_SIZE + length + ProtocolConstants.CRC_SIZE
        if (data.size < expected) throw FrameException("declared length $length exceeds buffer of ${data.size} bytes")
        if (data.size > expected) throw FrameException("trailing bytes after frame (${data.size - expected})")

        val computed = Crc16.compute(data, 0, ProtocolConstants.HEADER_SIZE + length)
        val received = Crc16.fromBytes(data, ProtocolConstants.HEADER_SIZE + length)
        if (computed != received) {
            throw FrameException("CRC mismatch: computed 0x%04X, received 0x%04X".format(computed, received))
        }
        return Frame(
            command = command,
            sequence = sequence,
            payload = data.copyOfRange(ProtocolConstants.OFFSET_PAYLOAD, ProtocolConstants.OFFSET_PAYLOAD + length),
        )
    }

    /**
     * Convenience for reading a framed reply off a stream: reads until a full,
     * CRC-valid frame is available, or throws [FrameException] on EOF/garbage.
     * Non-magic leading bytes are skipped (some chipsets emit event noise).
     *
     * [sniff] receives one debug line per read — junk bytes seen before the
     * magic and the raw frame hex — for diagnosing protocol mismatches.
     */
    fun readFrame(input: java.io.InputStream, sniff: ((String) -> Unit)? = null): Frame {
        val junk = StringBuilder()
        val header = ByteArray(ProtocolConstants.HEADER_SIZE)
        var magicPos = 0
        // Skip junk until we see the full magic sequence.
        while (magicPos < MAGIC.size) {
            val b = input.read()
            if (b == -1) {
                sniff?.invoke("EOF waiting for magic (skipped ${junk.length} junk bytes)")
                throw EOFException("stream ended while waiting for magic")
            }
            if (b == MAGIC[magicPos].toInt() and 0xFF) {
                header[magicPos] = b.toByte()
                magicPos++
            } else {
                if (junk.length < 96) junk.append("%02X ".format(b))
                // Re-scan from the start; a stray magic byte is handled next loop.
                magicPos = if (b == MAGIC[0].toInt() and 0xFF) 1 else 0
            }
        }
        if (junk.isNotEmpty()) sniff?.invoke("skipped non-magic bytes: $junk")
        // Read remaining fixed header (command, sequence, length).
        while (magicPos < ProtocolConstants.HEADER_SIZE) {
            val b = input.read()
            if (b == -1) {
                sniff?.invoke("EOF inside header")
                throw EOFException("stream ended inside header")
            }
            header[magicPos] = b.toByte()
            magicPos++
        }
        val length = ((header[ProtocolConstants.OFFSET_LENGTH].toInt() and 0xFF) shl 8) or
            (header[ProtocolConstants.OFFSET_LENGTH + 1].toInt() and 0xFF)
        val total = ProtocolConstants.HEADER_SIZE + length + ProtocolConstants.CRC_SIZE
        val buf = header.copyOf(total)
        var off = ProtocolConstants.HEADER_SIZE
        while (off < total) {
            val n = input.read(buf, off, total - off)
            if (n == -1) {
                sniff?.invoke("EOF inside payload/CRC (got $off of $total bytes)")
                throw EOFException("stream ended inside payload/CRC")
            }
            off += n
        }
        val frame = parse(buf)
        sniff?.invoke(
            "cmd=0x%02X seq=0x%02X len=%d raw=%s".format(
                frame.command, frame.sequence, frame.payload.size, buf.toHexString(48),
            ),
        )
        return frame
    }
}
