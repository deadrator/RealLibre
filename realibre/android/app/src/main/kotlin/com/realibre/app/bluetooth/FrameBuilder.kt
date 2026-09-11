package com.realibre.app.bluetooth

import java.io.EOFException
import java.io.IOException
import java.io.InputStream

/** Hex dump helper for wire logging (capped so the UI stays readable). */
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
 * Assembles and parses Oppo/Realme 0xAA frames:
 *
 * ```
 * [0]      preamble 0xAA
 * [1]      total length (frame size - 2)
 * [2..3]   zero
 * [4..5]   command code (uint16 LE)
 * [6]      sequence number
 * [7..8]   payload length (uint16 LE)
 * [9..N]   payload
 * ```
 *
 * No CRC, no auth — a frame is validated by preamble + length consistency.
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

    private val seqCounter = java.util.concurrent.atomic.AtomicInteger(0)

    fun nextSequence(): Int = seqCounter.incrementAndGet() and 0xFF

    /** Build a complete framed packet ready to write to the RFCOMM socket. */
    fun build(command: Int, sequence: Int, payload: ByteArray = ByteArray(0)): ByteArray {
        require(command in 0..0xFFFF) { "command out of range" }
        require(sequence in 0..0xFF) { "sequence out of range" }
        require(payload.size <= ProtocolConstants.MAX_MTU - ProtocolConstants.HEADER_SIZE) {
            "payload exceeds MTU budget"
        }

        val frame = ByteArray(ProtocolConstants.HEADER_SIZE + payload.size)
        frame[0] = ProtocolConstants.PREAMBLE.toByte()
        frame[1] = (frame.size - 2).toByte() // total length excludes preamble + length byte
        frame[2] = 0x00
        frame[3] = 0x00
        frame[4] = (command and 0xFF).toByte()          // command low byte (LE)
        frame[5] = ((command ushr 8) and 0xFF).toByte() // command high byte
        frame[6] = sequence.toByte()
        frame[7] = (payload.size and 0xFF).toByte()     // payload length (LE)
        frame[8] = ((payload.size ushr 8) and 0xFF).toByte()
        payload.copyInto(frame, ProtocolConstants.HEADER_SIZE)
        return frame
    }

    /**
     * Validate and decode a single complete frame from [data].
     * [data] must contain exactly one frame (no trailing bytes).
     */
    fun parse(data: ByteArray): Frame {
        if (data.size < ProtocolConstants.HEADER_SIZE) {
            throw FrameException("frame too short (${data.size} bytes)")
        }
        if (data[0].toInt() and 0xFF != ProtocolConstants.PREAMBLE) {
            throw FrameException("bad preamble 0x%02X".format(data[0].toInt() and 0xFF))
        }
        val totalLen = data[1].toInt() and 0xFF
        if (data.size != totalLen + 2) {
            throw FrameException("length byte says ${totalLen + 2}, got ${data.size} bytes")
        }
        val command = (data[4].toInt() and 0xFF) or ((data[5].toInt() and 0xFF) shl 8)
        val sequence = data[6].toInt() and 0xFF
        val payloadLen = (data[7].toInt() and 0xFF) or ((data[8].toInt() and 0xFF) shl 8)
        if (data.size < ProtocolConstants.HEADER_SIZE + payloadLen) {
            throw FrameException("payload length $payloadLen exceeds buffer ${data.size}")
        }
        return Frame(
            command = command,
            sequence = sequence,
            payload = data.copyOfRange(ProtocolConstants.HEADER_SIZE, ProtocolConstants.HEADER_SIZE + payloadLen),
        )
    }

    /**
     * Read one framed message off a stream. Bytes before the preamble are
     * logged through [sniff] (some buds emit event noise between frames).
     */
    fun readFrame(input: InputStream, sniff: ((String) -> Unit)? = null): Frame {
        var skipped = StringBuilder()
        // 1. Wait for the preamble.
        while (true) {
            val b = input.read()
            if (b == -1) {
                sniff?.invoke("EOF waiting for preamble (skipped ${skipped.length} chars)")
                throw EOFException("stream ended while waiting for preamble")
            }
            if (b == ProtocolConstants.PREAMBLE) break
            if (skipped.length < 96) skipped.append("%02X ".format(b))
        }
        if (skipped.isNotEmpty()) {
            sniff?.invoke("skipped non-preamble bytes: $skipped")
            skipped = StringBuilder()
        }
        // 2. Total length byte.
        val totalLen = input.read()
        if (totalLen == -1) throw EOFException("stream ended inside header")
        // 3. Read the rest of the frame (totalLen counts bytes after the length byte).
        val buf = ByteArray(totalLen + 2)
        buf[0] = ProtocolConstants.PREAMBLE.toByte()
        buf[1] = totalLen.toByte()
        var off = 2
        while (off < buf.size) {
            val n = input.read(buf, off, buf.size - off)
            if (n == -1) {
                sniff?.invoke("EOF inside frame (got $off of ${buf.size} bytes)")
                throw EOFException("stream ended inside frame")
            }
            off += n
        }
        val frame = parse(buf)
        sniff?.invoke(
            "cmd=0x%04X seq=0x%02X len=%d raw=%s".format(
                frame.command, frame.sequence, frame.payload.size, buf.toHexString(48),
            ),
        )
        return frame
    }
}
