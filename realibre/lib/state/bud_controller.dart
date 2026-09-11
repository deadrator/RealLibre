import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';

import '../core/constants/bud_enums.dart';
import '../core/platform/method_channels.dart';

/// Widget testing seam so UI tests can stub the platform side.
BudChannels budChannelsInstance = BudChannels();

/// Central controller: owns connection lifecycle, mirrors telemetry streams
/// into state, and performs every attribute write through [BudChannels].
class BudController extends ChangeNotifier {
  BudController({BudChannels? channels}) : _channels = channels ?? budChannelsInstance;

  final BudChannels _channels;

  /// Hard ceiling on any single platform call in the connect flow. If native
  /// never answers (old build, wedged channel), the UI still recovers instead
  /// of spinning on "Authenticating…" forever.
  static const Duration _connectStepTimeout = Duration(seconds: 25);
  StreamSubscription<BudTelemetryEvent>? _sub;
  ConnectionState _state = ConnectionState.disconnected;
  BatterySnapshot _battery = const BatterySnapshot(left: 0, right: 0, caseLevel: 0, source: 'rfcomm');
  NoiseMode _noiseMode = NoiseMode.off;
  AncLevel _ancLevel = AncLevel.moderate;
  EqMode _eqMode = EqMode.defaultMode;
  final Set<String> _toggles = {};
  String? _lastError;
  bool _keepAlive = true;
  bool _autoConnectAttempted = false;

  /// Ring buffer of native wire-debug lines (hex frames, handshake steps)
  /// shown on the dashboard's debug console — diagnosing a wrong protocol
  /// assumption should not require adb/logcat.
  final List<String> _debugLines = [];
  List<String> get debugLines => List.unmodifiable(_debugLines);

  /// Whether the silent auto-connect has already been tried this session —
  /// after it runs, the pairing screen is only shown if it failed.
  bool get autoConnectAttempted => _autoConnectAttempted;

  ConnectionState get state => _state;
  BatterySnapshot get battery => _battery;
  NoiseMode get noiseMode => _noiseMode;
  AncLevel get ancLevel => _ancLevel;
  EqMode get eqMode => _eqMode;
  String? get lastError => _lastError;
  bool get keepAlive => _keepAlive;
  bool get isConnected => _state == ConnectionState.connected;
  bool isToggleOn(String key) => _toggles.contains(key);

  /// Begin listening to native events; safe to call multiple times.
  void attach() {
    _sub ??= _channels.events().listen(_onEvent, onError: (Object e) {
      _lastError = e.toString();
      notifyListeners();
    });
  }

  void _onEvent(BudTelemetryEvent event) {
    if (event.state != null) _state = event.state!;
    if (event.battery != null) _battery = event.battery!;
    if (event.error != null) _lastError = event.error;
    if (event.debugLine != null) {
      _debugLines.add(event.debugLine!);
      if (_debugLines.length > 80) _debugLines.removeRange(0, _debugLines.length - 80);
    }
    notifyListeners();
  }

  Future<void> initialize() async {
    attach();
    if (!await _channels.hasPermissions()) await _channels.requestPermissions();
    _keepAlive = await _channels.getKeepAlive();
    notifyListeners();
  }

  /// Best-effort silent reconnect for the common case: the buds are already
  /// bonded and usually already streaming audio via the OS Bluetooth stack —
  /// no pairing dialog needed, so skip the pairing screen entirely.
  /// Only opens the RFCOMM control channel when the buds are bonded.
  Future<void> autoConnect() async {
    if (_autoConnectAttempted) return;
    _autoConnectAttempted = true;
    if (!await _channels.hasPermissions()) {
      await _channels.requestPermissions();
      // The grant arrives via the system dialog; if it's still pending the
      // user can connect manually from the pairing screen afterwards.
      if (!await _channels.hasPermissions()) return;
    }
    try {
      if (!await _channels.isBonded().timeout(_connectStepTimeout)) {
        return; // never paired — let the pairing screen take over
      }
      final ok = await _channels.connect().timeout(
            _connectStepTimeout,
            onTimeout: () => false,
          );
      if (ok) {
        _lastError = null;
        await refreshBattery();
        await _channels.startBatteryService();
      }
      // On failure the state flips to failed/disconnected via the event
      // channel and the UI falls back to the pairing screen with the reason.
    } on PlatformException catch (e) {
      _lastError = e.message ?? e.code;
      notifyListeners();
    } on TimeoutException {
      _lastError = 'Connection timed out';
      notifyListeners();
    } catch (_) {
      // Silent: never block startup on a background reconnect.
    }
  }

  /// Manual reconnect from the dashboard after a drop (tap the status bar).
  Future<void> reconnect() async {
    try {
      final ok = await _channels.connect().timeout(
            _connectStepTimeout,
            onTimeout: () => false,
          );
      if (ok) {
        _lastError = null;
        await refreshBattery();
        await _channels.startBatteryService();
      }
    } on PlatformException catch (e) {
      _lastError = e.message ?? e.code;
      notifyListeners();
    } on TimeoutException {
      _lastError = 'Connection timed out';
      notifyListeners();
    } catch (_) {
      // Non-fatal; the dashboard badge already shows the offline state.
    }
  }

  Future<bool> pairAndConnect() async {
    try {
      if (!await _channels.isBonded().timeout(_connectStepTimeout)) {
        if (!await _channels.pair().timeout(_connectStepTimeout)) {
          _lastError = 'Pairing was cancelled or failed';
          notifyListeners();
          return false;
        }
      }
      final ok = await _channels.connect().timeout(
            _connectStepTimeout,
            onTimeout: () => throw PlatformException(
              code: 'CONNECT_TIMEOUT',
              message: 'Connection timed out — make sure the buds are on and in range, then retry',
            ),
          );
      if (ok) {
        _lastError = null;
        await refreshBattery();
        await _channels.startBatteryService();
      }
      return ok;
    } on PlatformException catch (e) {
      _lastError = e.message ?? e.code;
      notifyListeners();
      return false;
    } on TimeoutException catch (e) {
      _lastError = e.message ?? 'Connection timed out';
      notifyListeners();
      return false;
    } catch (e) {
      // Never let an unexpected native error escape: the pairing screen
      // relies on a clean false to stop its spinner and show the message.
      _lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await _channels.disconnect();
    } on PlatformException catch (e) {
      _lastError = e.message ?? e.code;
    }
    _state = ConnectionState.disconnected;
    notifyListeners();
  }

  Future<void> refreshBattery() async {
    try {
      _battery = await _channels.queryBattery();
      notifyListeners();
    } on PlatformException catch (e) {
      _lastError = e.message ?? e.code;
      notifyListeners();
    }
  }

  Future<bool> triggerBatteryPopup() async {
    try {
      await refreshBattery();
      return await _channels.triggerBatteryPopup();
    } on PlatformException catch (e) {
      _lastError = e.message ?? e.code;
      notifyListeners();
      return false;
    }
  }

  Future<void> setNoiseMode(NoiseMode mode) async {
    final prev = _noiseMode;
    _noiseMode = mode; // optimistic for snappy crossfade
    notifyListeners();
    try {
      await _channels.setNoiseMode(mode);
      _lastError = null;
    } on PlatformException catch (e) {
      _noiseMode = prev;
      _lastError = e.message ?? e.code;
    }
    notifyListeners();
  }

  Future<void> setAncLevel(AncLevel level) async {
    final prev = _ancLevel;
    _ancLevel = level;
    notifyListeners();
    try {
      await _channels.setAncLevel(level);
    } on PlatformException catch (e) {
      _ancLevel = prev;
      _lastError = e.message ?? e.code;
    }
    notifyListeners();
  }

  Future<void> setEqMode(EqMode mode) async {
    final prev = _eqMode;
    _eqMode = mode;
    notifyListeners();
    try {
      await _channels.setEqMode(mode);
    } on PlatformException catch (e) {
      _eqMode = prev;
      _lastError = e.message ?? e.code;
    }
    notifyListeners();
  }

  Future<void> setToggle(String key, bool on) async {
    final had = _toggles.contains(key);
    void apply(bool v) => v ? _toggles.add(key) : _toggles.remove(key);
    apply(on);
    notifyListeners();
    try {
      switch (key) {
        case 'gaming':
          await _channels.setGaming(on);
          break;
        case 'spatial':
          await _channels.setSpatialAudio(on);
          break;
        case 'volumeEnhancer':
          await _channels.setVolumeEnhancer(on);
          break;
        case 'windNoise':
          await _channels.setWindNoise(on);
          break;
        case 'enhanceVoices':
          await _channels.setEnhanceVoices(on);
          break;
        case 'multipoint':
          await _channels.setMultipoint(on);
          break;
        case 'fitTest':
          await _channels.triggerFitTest();
          break;
        default:
          break;
      }
      _lastError = null;
    } on PlatformException catch (e) {
      apply(had);
      _lastError = e.message ?? e.code;
    }
    notifyListeners();
  }

  Future<void> setKeepAlive(bool value) async {
    _keepAlive = value;
    notifyListeners();
    await _channels.setKeepAlive(value);
  }

  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }
}
