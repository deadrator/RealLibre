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
  StreamSubscription<BudTelemetryEvent>? _sub;
  ConnectionState _state = ConnectionState.disconnected;
  BatterySnapshot _battery = const BatterySnapshot(left: 0, right: 0, caseLevel: 0, source: 'rfcomm');
  NoiseMode _noiseMode = NoiseMode.off;
  AncLevel _ancLevel = AncLevel.moderate;
  EqMode _eqMode = EqMode.Default_;
  final Set<String> _toggles = {};
  String? _lastError;
  bool _keepAlive = true;

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
    notifyListeners();
  }

  Future<void> initialize() async {
    attach();
    if (!await _channels.hasPermissions()) await _channels.requestPermissions();
    _keepAlive = await _channels.getKeepAlive();
    notifyListeners();
  }

  Future<bool> pairAndConnect() async {
    try {
      if (!await _channels.isBonded()) {
        await _channels.pair();
      }
      final ok = await _channels.connect();
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
    }
  }

  Future<void> disconnect() async {
    await _channels.disconnect();
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
