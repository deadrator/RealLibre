package com.realibre.app.bluetooth

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.util.Log
import java.io.EOFException
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
/**
 * Owns the single authenticated RFCOMM socket to the buds.
 *
 * Every outbound byte goes through [FrameBuilder.build]; every inbound byte is
 * CRC-checked by [FrameBuilder.parse]. The handshake in [HmacAuth] must finish
 * before [isAuthenticated] flips true — callers gate Cmd 0x03/0x04 on that.
 *
 * Max 1 active connection: one socket per process. Calling [connect] while
 * connected is a no-op.
 */
@SuppressLint("MissingPermission")
object RfcommManager {

    private const val TAG = "RfcommManager"

    enum class ConnectionState { DISCONNECTED, CONNECTING, AUTHENTICATING, CONNECTED, FAILED }

    data class Battery(
        val left: Int,
        val right: Int,
        val case: Int,
    ) {
        companion object {
            /** Cmd 0x03 payload: L%, R%, Case% as true 1% integers. */
            fun fromStatusPayload(p: ByteArray): Battery? {
                if (p.size < 3) return null
                fun clamp(v: Int) = (v and 0xFF).coerceIn(0, 100)
                return Battery(clamp(p[0].toInt()), clamp(p[1].toInt()), clamp(p[2].toInt()))
            }
        }
    }

    sealed class Incoming {
        data class BatteryLevel(val battery: Battery) : Incoming()
        data class FrameReceived(val frame: FrameBuilder.Frame) : Incoming()
        data class Error(val message: String) : Incoming()
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val ioExecutor = Executors.newSingleThreadExecutor { r -> Thread(r, "rfcomm-io") }
    private val ioDispatcher = ioExecutor.asCoroutineDispatcher()

    private val _state = MutableStateFlow(ConnectionState.DISCONNECTED)
    val state: StateFlow<ConnectionState> = _state

    private val _incoming = MutableSharedFlow<Incoming>(
        replay = 0, extraBufferCapacity = 64, onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )
    val incoming: SharedFlow<Incoming> = _incoming

    /** Wire-level diagnostics (hex dumps, step failures) surfaced to the UI
     *  so a protocol mismatch can be diagnosed without adb. */
    private val _debug = MutableSharedFlow<String>(
        replay = 64, extraBufferCapacity = 256, onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )
    val debug: SharedFlow<String> = _debug

    private fun logWire(message: String) {
        Log.d(TAG, message)
        _debug.tryEmit(message)
    }

    private var socket: BluetoothSocket? = null
    private var input: InputStream? = null
    private var output: OutputStream? = null
    private val sequence = AtomicInteger(0)
    private val authed = AtomicBoolean(false)
    private var readerJob: kotlinx.coroutines.Job? = null
    /** Bumped per connection attempt so stale reader loops can't tear down
     *  a newer session's socket in their finally block. */
    private val generation = AtomicLong(0)
    /** Guards against the app and the QS tile dialing at the same time. */
    private val connecting = AtomicBoolean(false)

    val isAuthenticated: Boolean get() = authed.get()
    val isConnected: Boolean get() = _state.value == ConnectionState.CONNECTED

    private fun nextSeq(): Int = sequence.incrementAndGet() and 0xFF

    /** Connect, run the auth handshake, then start the reader loop.
     *  Every blocking step is bounded by a timeout and runs off the main
     *  thread, so a silent bud can never wedge or ANR the UI. */
    suspend fun connect(context: Context) {
        if (isConnected) return
        disconnect() // ensure clean slate

        val adapter = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
            ?: throw IOException("no bluetooth adapter")
        if (!adapter.isEnabled) throw IOException("bluetooth is off")

        val device: BluetoothDevice = adapter.getRemoteDevice(ProtocolConstants.DEVICE_MAC)
        if (!connecting.compareAndSet(false, true)) {
            throw IOException("connection already in progress")
        }
        val session = generation.incrementAndGet()
        try {
            _state.value = ConnectionState.CONNECTING
            val uuid = UUID.fromString(ProtocolConstants.SPP_UUID)
            withContext(ioDispatcher) {
                var lastError: Exception? = null
                // SPP SDP lookup first, then insecure variant, then raw channel 1.
                val attempts = listOf<Pair<String, () -> BluetoothSocket>>(
                    "SPP (secure)" to { device.createRfcommSocketToServiceRecord(uuid) },
                    "SPP (insecure)" to { device.createInsecureRfcommSocketToServiceRecord(uuid) },
                    "raw channel 1" to {
                        device.javaClass
                            .getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
                            .invoke(device, ProtocolConstants.RFCOMM_CHANNEL) as BluetoothSocket
                    },
                )
                // Fresh thread per attempt: BluetoothSocket.connect() ignores
                // SoTimeouts and can hang for minutes, and a timed-out dial
                // stays blocked until its socket is closed from this side.
                val dialExecutor = Executor { command ->
                    Thread(command, "rfcomm-dial").apply { isDaemon = true }.start()
                }
                for ((label, factory) in attempts) {
                    logWire("dialing $label …")
                    var dialSocket: BluetoothSocket? = null
                    val future = CompletableFuture.supplyAsync({
                        dialSocket = factory()
                        adapter.cancelDiscovery()
                        dialSocket!!.connect()
                        dialSocket!!
                    }, dialExecutor)
                    try {
                        val s = future.get(ProtocolConstants.CONNECT_TIMEOUT_MS, TimeUnit.MILLISECONDS)
                        socket = s
                        input = s.inputStream
                        output = s.outputStream
                        logWire("socket connected via $label")
                        lastError = null
                        break
                    } catch (e: TimeoutException) {
                        future.cancel(true)
                        // Closing the socket aborts the blocked connect() on the dial thread.
                        try { dialSocket?.close() } catch (_: Exception) {}
                        lastError = IOException("$label timed out after ${ProtocolConstants.CONNECT_TIMEOUT_MS / 1000}s")
                        logWire("$label timed out")
                    } catch (e: ExecutionException) {
                        try { dialSocket?.close() } catch (_: Exception) {}
                        lastError = e.cause as? Exception ?: IOException(e.cause)
                        logWire("$label failed: ${lastError?.message}")
                    }
                    closeSocketQuietly()
                }
                lastError?.let { throw it }
            }

            _state.value = ConnectionState.AUTHENTICATING
            // Bounded handshake: on timeout the socket is closed by the outer
            // catch below, which also unblocks the stuck read on rfcomm-io.
            withTimeoutOrNull(ProtocolConstants.HANDSHAKE_TIMEOUT_MS) {
                withContext(ioDispatcher) { runHandshake() }
            } ?: throw IOException("auth handshake timed out after ${ProtocolConstants.HANDSHAKE_TIMEOUT_MS / 1000}s")
        } catch (e: kotlinx.coroutines.CancellationException) {
            closeSocketQuietly()
            authed.set(false)
            throw e
        } catch (e: Exception) {
            closeSocketQuietly()
            authed.set(false)
            _state.value = ConnectionState.FAILED
            throw if (e is IOException) e else IOException("RFCOMM connect failed", e)
        } finally {
            connecting.set(false)
        }

        authed.set(true)
        _state.value = ConnectionState.CONNECTED
        startReader(session)
    }

    /** Cmd 0x01 → verify → Cmd 0x02 → expect Cmd 0x02 confirm.
     *  Every step is wire-logged; failures carry the raw bytes so a wrong
     *  protocol assumption (magic, CRC, command IDs) is diagnosable in-app. */
    private fun runHandshake() {
        val clientRandom = HmacAuth.newClientChallenge()
        writeRaw(FrameBuilder.build(ProtocolConstants.CMD_AUTH_CHALLENGE, nextSeq(), clientRandom))

        val reply = try {
            FrameBuilder.readFrame(input ?: throw IOException("stream lost")) { logWire("← $it") }
        } catch (e: EOFException) {
            throw HmacAuth.AuthException(
                "buds closed the stream during the Cmd 0x01 exchange — " +
                    "they never answered the RMV-framed challenge (protocol data may be wrong)",
            )
        } catch (e: FrameBuilder.FrameException) {
            throw HmacAuth.AuthException("${e.message} — buds speak a different frame format")
        }
        if (reply.command != ProtocolConstants.CMD_AUTH_CHALLENGE) {
            throw HmacAuth.AuthException(
                "expected Cmd 0x01 reply, got 0x%02X (payload %s)".format(reply.command, reply.payload.toHexString()),
            )
        }
        val earbudRandom = try {
            HmacAuth.verifyChallengeReply(reply.payload, clientRandom)
        } catch (e: HmacAuth.AuthException) {
            throw HmacAuth.AuthException("${e.message} (reply payload ${reply.payload.toHexString()})")
        }

        writeRaw(
            FrameBuilder.build(
                ProtocolConstants.CMD_AUTH_RESPONSE,
                nextSeq(),
                HmacAuth.buildResponsePayload(earbudRandom),
            )
        )

        val confirm = try {
            FrameBuilder.readFrame(input ?: throw IOException("stream lost")) { logWire("← $it") }
        } catch (e: EOFException) {
            throw HmacAuth.AuthException("buds closed the stream awaiting the Cmd 0x02 confirm")
        } catch (e: FrameBuilder.FrameException) {
            throw HmacAuth.AuthException("${e.message} — buds speak a different frame format")
        }
        if (confirm.command != ProtocolConstants.CMD_AUTH_RESPONSE) {
            throw HmacAuth.AuthException(
                "expected Cmd 0x02 confirm, got 0x%02X".format(confirm.command),
            )
        }
        logWire("handshake complete — session unlocked")
    }

    private fun startReader(session: Long) {
        readerJob?.cancel()
        readerJob = scope.launch(ioDispatcher) {
            val stream = input ?: return@launch
            try {
                while (isConnected && isActive) {
                    val frame = try {
                        FrameBuilder.readFrame(stream) { logWire("← $it") }
                    } catch (e: java.io.EOFException) {
                        break
                    } catch (e: Exception) {
                        _incoming.emit(Incoming.Error(e.message ?: "read error"))
                        break
                    }
                    when (frame.command) {
                        ProtocolConstants.CMD_STATUS_QUERY -> {
                            Battery.fromStatusPayload(frame.payload)?.let {
                                _incoming.emit(Incoming.BatteryLevel(it))
                            }
                        }
                        else -> _incoming.emit(Incoming.FrameReceived(frame))
                    }
                }
            } finally {
                // The loop exits on EOF, read error, disconnect(), or state
                // change — tear the session down in every case so the app can
                // reconnect cleanly instead of sitting on a stale socket.
                // A superseded reader (stale session) must not touch the
                // current socket.
                if (generation.get() == session) {
                    closeSocketQuietly()
                    authed.set(false)
                    if (_state.value == ConnectionState.CONNECTED) {
                        _state.value = ConnectionState.DISCONNECTED
                    }
                }
            }
        }
    }

    /**
     * Send Cmd 0x03 and await the status reply (true 1% integers).
     * Subscribes BEFORE writing so the reply cannot slip past the collector,
     * then awaits it with a timeout.
     */
    suspend fun queryBattery(): Battery = coroutineScope {
        requireAuthenticated()
        val waiter = async(start = CoroutineStart.UNDISPATCHED) {
            incoming.filterIsInstance<Incoming.BatteryLevel>().first()
        }
        try {
            withContext(ioDispatcher) {
                writeRaw(FrameBuilder.build(ProtocolConstants.CMD_STATUS_QUERY, nextSeq(), ByteArray(0)))
            }
            val reply = withTimeoutOrNull(2_500L) { waiter.await() }
            reply?.battery ?: throw IOException("timed out waiting for battery status")
        } catch (e: Throwable) {
            waiter.cancel()
            throw e
        }
    }

    /** Send Cmd 0x04 ATTR_SET with payload [0x02, attrId, value]. */
    suspend fun setAttribute(attrId: Int, value: Int) {
        requireAuthenticated()
        val payload = byteArrayOf(
            ProtocolConstants.ATTR_PAYLOAD_LENGTH.toByte(),
            attrId.toByte(),
            value.toByte(),
        )
        val frame = FrameBuilder.build(ProtocolConstants.CMD_ATTR_SET, nextSeq(), payload)
        withContext(ioDispatcher) { writeRaw(frame) }
    }

    private fun requireAuthenticated() {
        if (!authed.get()) throw IOException("not authenticated — run connect() first")
    }

    /** The only sanctioned outbound path: framed + CRC'd. */
    private fun writeRaw(bytes: ByteArray) {
        val out = output ?: throw IOException("socket not connected")
        logWire("→ ${bytes.toHexString(48)}")
        synchronized(out) {
            out.write(bytes)
            out.flush()
        }
    }

    @Synchronized
    fun disconnect() {
        readerJob?.cancel()
        readerJob = null
        closeSocketQuietly()
        authed.set(false)
        if (_state.value != ConnectionState.FAILED) _state.value = ConnectionState.DISCONNECTED
    }

    private fun closeSocketQuietly() {
        try { socket?.close() } catch (_: Exception) {}
        socket = null
        input = null
        output = null
    }
}
