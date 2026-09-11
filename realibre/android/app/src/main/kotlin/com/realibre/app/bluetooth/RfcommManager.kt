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
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
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
 * Owns the single RFCOMM socket to the buds and speaks the real
 * Oppo/Realme 0xAA protocol (see [ProtocolConstants]).
 *
 * Every outbound byte goes through [FrameBuilder.build]; every inbound frame
 * is decoded by [FrameBuilder.parse]. There is no authentication handshake on
 * this protocol — after the socket opens we run the init sequence (queries +
 * subscriptions) and the buds start answering.
 *
 * Max 1 active connection: one socket per process.
 */
@SuppressLint("MissingPermission")
object RfcommManager {

    private const val TAG = "RfcommManager"

    enum class ConnectionState { DISCONNECTED, CONNECTING, AUTHENTICATING, CONNECTED, FAILED }

    data class Battery(
        val left: Int,
        val right: Int,
        val case: Int,
        val leftCharging: Boolean = false,
        val rightCharging: Boolean = false,
        val caseCharging: Boolean = false,
    ) {
        companion object {
            /** Unknown/absent sentinel used when a bud doesn't report. */
            const val UNKNOWN: Int = -1
        }
    }

    sealed class Incoming {
        data class BatteryLevel(val battery: Battery) : Incoming()
        data class NoiseModeChanged(val value: Int) : Incoming()
        data class GameModeChanged(val enabled: Boolean) : Incoming()
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

    /** Wire-level diagnostics (hex dumps, step failures) surfaced to the UI. */
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
    private val authed = AtomicBoolean(false)
    /** Bumped per connection attempt so stale reader loops can't tear down
     *  a newer session's socket in their finally block. */
    private val generation = AtomicLong(0)
    /** Guards against the app and the QS tile dialing at the same time. */
    private val connecting = AtomicBoolean(false)
    private var readerJob: kotlinx.coroutines.Job? = null

    val isAuthenticated: Boolean get() = authed.get()
    val isConnected: Boolean get() = _state.value == ConnectionState.CONNECTED

    /**
     * Connect, run the Oppo init sequence (queries + subscriptions), then
     * start the reader loop. Every blocking step is bounded by a timeout and
     * runs off the main thread.
     */
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

                // No handshake on this protocol — mark authenticated and run
                // the init sequence (Gadgetbridge-style: queries + subs).
                authed.set(true)
                _state.value = ConnectionState.CONNECTED
                startReader(session)
                runInitSequence()
            }
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
    }

    /**
     * Init sequence after connect: query current ANC mode + misc config,
     * subscribe to push updates, ask for firmware and battery. The first
     * battery request is often ignored by the buds, so it is retried.
     */
    private fun runInitSequence() {
        logWire("running init sequence")
        // Query current ANC mode (reply: ANC_CONFIG_RET).
        writeRaw(
            FrameBuilder.build(
                ProtocolConstants.CMD_ANC_CONFIG_REQ, FrameBuilder.nextSequence(),
                byteArrayOf(ProtocolConstants.ANC_TYPE_MODE.toByte(), 0x01),
            ),
        )
        // Query game mode + multipoint state.
        writeRaw(
            FrameBuilder.build(
                ProtocolConstants.CMD_MISC_CONFIG_REQ, FrameBuilder.nextSequence(),
                byteArrayOf(0x02, ProtocolConstants.MISC_GAME_MODE.toByte(), ProtocolConstants.MISC_MULTIPOINT.toByte()),
            ),
        )
        // Subscribe to push updates: battery, ANC selector, game mode.
        writeRaw(
            FrameBuilder.build(
                ProtocolConstants.CMD_SUBSCRIPTION_SET, FrameBuilder.nextSequence(),
                byteArrayOf(
                    0x09,
                    ProtocolConstants.SUB_BATTERY.toByte(),
                    ProtocolConstants.SUB_ANC_SELECTOR.toByte(),
                    ProtocolConstants.SUB_GAME_MODE.toByte(),
                ),
            ),
        )
        // Firmware version (nice for the debug console).
        writeRaw(FrameBuilder.build(ProtocolConstants.CMD_FIRMWARE_GET, FrameBuilder.nextSequence()))
        // Battery now; the reader emits BatteryLevel on BATTERY_RET.
        scope.launch(ioDispatcher) { queryBatteryWithRetry() }
    }

    /**
     * Send Cmd BATTERY_REQ and await BATTERY_RET (true 1% integers).
     * The buds sometimes ignore the first request after connect — retry up
     * to 3 times before giving up.
     */
    suspend fun queryBattery(): Battery {
        requireAuthenticated()
        repeat(2) { attempt ->
            val battery = tryBatteryOnce()
            if (battery != null) return battery
            logWire("battery attempt ${attempt + 1} got no reply, retrying")
            delay(400)
        }
        return tryBatteryOnce() ?: throw IOException("buds never answered the battery request")
    }

    private suspend fun tryBatteryOnce(): Battery? = coroutineScope {
        val waiter = async(start = CoroutineStart.UNDISPATCHED) {
            incoming.filterIsInstance<Incoming.BatteryLevel>().first()
        }
        try {
            withContext(ioDispatcher) {
                writeRaw(FrameBuilder.build(ProtocolConstants.CMD_BATTERY_REQ, FrameBuilder.nextSequence()))
            }
            withTimeoutOrNull(ProtocolConstants.RESPONSE_TIMEOUT_MS) { waiter.await() }?.battery
        } catch (e: Throwable) {
            waiter.cancel()
            throw e
        }
    }

    private suspend fun queryBatteryWithRetry() {
        runCatching { queryBattery() }
            .onFailure { logWire("initial battery poll failed: ${it.message}") }
    }

    /**
     * Send a battery request without waiting for the reply (the reader pushes
     * BATTERY_RET into the event stream). Used by the notification refresh.
     */
    suspend fun requestBatteryAsync() {
        requireAuthenticated()
        withContext(ioDispatcher) {
            writeRaw(FrameBuilder.build(ProtocolConstants.CMD_BATTERY_REQ, FrameBuilder.nextSequence()))
        }
    }

    /** ANC mode set: payload [ANC_TYPE_MODE, 0x01, value]. */
    suspend fun setNoiseMode(value: Int) {
        requireAuthenticated()
        val payload = byteArrayOf(
            ProtocolConstants.ANC_TYPE_MODE.toByte(),
            0x01,
            value.toByte(),
        )
        withContext(ioDispatcher) {
            writeRaw(FrameBuilder.build(ProtocolConstants.CMD_ANC_CONFIG_SET, FrameBuilder.nextSequence(), payload))
        }
    }

    /** Game (low latency) mode on/off via MISC_CONFIG_SET. */
    suspend fun setGameMode(enabled: Boolean) {
        requireAuthenticated()
        val payload = byteArrayOf(ProtocolConstants.MISC_GAME_MODE.toByte(), if (enabled) 0x01 else 0x00)
        withContext(ioDispatcher) {
            writeRaw(FrameBuilder.build(ProtocolConstants.CMD_MISC_CONFIG_SET, FrameBuilder.nextSequence(), payload))
        }
    }

    /** Multipoint (dual connection) on/off via MISC_CONFIG_SET. */
    suspend fun setMultipoint(enabled: Boolean) {
        requireAuthenticated()
        val payload = byteArrayOf(ProtocolConstants.MISC_MULTIPOINT.toByte(), if (enabled) 0x01 else 0x00)
        withContext(ioDispatcher) {
            writeRaw(FrameBuilder.build(ProtocolConstants.CMD_MISC_CONFIG_SET, FrameBuilder.nextSequence(), payload))
        }
    }

    /** Make the buds play a locator tone (FIND_DEVICE_REQ, 0x01=on 0x00=off). */
    suspend fun findDevice(start: Boolean) {
        requireAuthenticated()
        withContext(ioDispatcher) {
            writeRaw(
                FrameBuilder.build(
                    ProtocolConstants.CMD_FIND_DEVICE_REQ, FrameBuilder.nextSequence(),
                    byteArrayOf(if (start) 0x01 else 0x00),
                ),
            )
        }
    }

    /**
     * Parse a BATTERY_RET / battery subscription payload:
     * `[status, count, (index, levelByte)...]` where index 1=L, 2=R, 3=case
     * and levelByte & 0x7F is the percent, & 0x80 the charging flag.
     */
    private fun parseBatteryPayload(payload: ByteArray): Battery? {
        if (payload.size < 2) return null
        if (payload[0].toInt() != 0x00) {
            logWire("battery ret status=${payload[0]}")
            return null
        }
        var left = Battery.UNKNOWN
        var right = Battery.UNKNOWN
        var case = Battery.UNKNOWN
        var leftCharging = false
        var rightCharging = false
        var caseCharging = false
        var i = 2
        while (i + 1 < payload.size) {
            val index = payload[i].toInt() and 0xFF
            val levelByte = payload[i + 1].toInt() and 0xFF
            i += 2
            if (index == 0xFF) continue
            val level = levelByte and 0x7F
            val charging = (levelByte and 0x80) != 0
            when (index) {
                1 -> { left = level; leftCharging = charging }
                2 -> { right = level; rightCharging = charging }
                3 -> { if (!(level == 0 && !charging)) { case = level; caseCharging = charging } }
                else -> logWire("unknown battery index $index")
            }
        }
        return Battery(left, right, case, leftCharging, rightCharging, caseCharging)
    }

    private fun startReader(session: Long) {
        readerJob?.cancel()
        // Pooled dispatcher: the loop blocks in read() for the lifetime of the
        // socket, so it must NOT occupy the single-thread ioDispatcher that
        // writeRaw needs — that would deadlock every later command.
        readerJob = scope.launch(Dispatchers.IO) {
            val stream = input ?: return@launch
            try {
                while (isConnected && isActive) {
                    val frame = try {
                        FrameBuilder.readFrame(stream) { logWire("← $it") }
                    } catch (e: EOFException) {
                        break
                    } catch (e: Exception) {
                        _incoming.emit(Incoming.Error(e.message ?: "read error"))
                        break
                    }
                    when (frame.command) {
                        ProtocolConstants.CMD_BATTERY_RET -> {
                            parseBatteryPayload(frame.payload)?.let {
                                _incoming.emit(Incoming.BatteryLevel(it))
                            }
                        }
                        ProtocolConstants.CMD_SUBSCRIPTION_RET -> {
                            when ((frame.payload.getOrNull(0)?.toInt() ?: -1) and 0xFF) {
                                ProtocolConstants.SUB_BATTERY -> {
                                    parseBatteryPayload(frame.payload)?.let {
                                        _incoming.emit(Incoming.BatteryLevel(it))
                                    }
                                }
                                ProtocolConstants.SUB_ANC_SELECTOR -> {
                                    val mode = (frame.payload.getOrNull(2)?.toInt() ?: -1) and 0xFF
                                    _incoming.emit(Incoming.NoiseModeChanged(mode))
                                }
                                ProtocolConstants.SUB_GAME_MODE -> {
                                    _incoming.emit(Incoming.GameModeChanged(frame.payload.getOrNull(1) == 0x01.toByte()))
                                }
                            }
                        }
                        ProtocolConstants.CMD_ANC_CONFIG_RET -> {
                            // [status, type, ?, value]
                            val type = (frame.payload.getOrNull(1)?.toInt() ?: -1) and 0xFF
                            if (type == ProtocolConstants.ANC_TYPE_MODE) {
                                val mode = (frame.payload.getOrNull(3)?.toInt() ?: -1) and 0xFF
                                _incoming.emit(Incoming.NoiseModeChanged(mode))
                            }
                        }
                        ProtocolConstants.CMD_MISC_CONFIG_RET -> {
                            for (j in 2 until frame.payload.size - 1 step 2) {
                                val type = frame.payload[j].toInt() and 0xFF
                                val value = frame.payload[j + 1].toInt() and 0xFF
                                if (type == ProtocolConstants.MISC_GAME_MODE) {
                                    _incoming.emit(Incoming.GameModeChanged(value == 1))
                                }
                            }
                        }
                        else -> _incoming.emit(Incoming.FrameReceived(frame))
                    }
                }
            } finally {
                // Tear down on any exit so the app can reconnect cleanly; a
                // superseded reader must not touch the current socket.
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

    private fun requireAuthenticated() {
        if (!authed.get()) throw IOException("not connected — run connect() first")
    }

    /** The only sanctioned outbound path. */
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
