/// Typed wrapper over the `realibre/methods` + `realibre/events` platform
/// channels. All bud writes funnel through here and end up in the framed
/// native path (real Oppo/Realme protocol).
library;

import 'dart:async';

import 'package:flutter/services.dart';

import '../constants/bud_enums.dart';

enum ConnectionState { disconnected, connecting, authenticating, connected, failed }

class BatterySnapshot {
  const BatterySnapshot({
    required this.left,
    required this.right,
    required this.caseLevel,
    required this.source,
    this.timestamp,
  });

  final int left;
  final int right;
  final int caseLevel;
  final String source; // "rfcomm" (1% true) or "hfp"/"fastpair" (coarse)
  final int? timestamp;

  static BatterySnapshot fromMap(Object? map) {
    final m = map as Map<Object?, Object?>?;
    return BatterySnapshot(
      left: (m?['left'] as num?)?.toInt() ?? 0,
      right: (m?['right'] as num?)?.toInt() ?? 0,
      caseLevel: (m?['case'] as num?)?.toInt() ?? 0,
      source: (m?['source'] as String?) ?? 'rfcomm',
      timestamp: (m?['timestamp'] as num?)?.toInt(),
    );
  }
}

class BudTelemetryEvent {
  const BudTelemetryEvent({
    this.battery,
    this.error,
    this.state,
    this.debugLine,
    this.noiseMode,
    this.gameMode,
  });
  final BatterySnapshot? battery;
  final String? error;
  final ConnectionState? state;
  final String? debugLine;
  final int? noiseMode;
  final bool? gameMode;
}

class BudChannels {
  BudChannels();

  static const MethodChannel _methods = MethodChannel('realibre/methods');
  static const EventChannel _events = EventChannel('realibre/events');

  Stream<BudTelemetryEvent>? _eventStream;

  /// Single broadcast stream of connection + battery + error events.
  Stream<BudTelemetryEvent> events() {
    return _eventStream ??= _events
        .receiveBroadcastStream()
        .map<BudTelemetryEvent>((event) {
          final map = event as Map<Object?, Object?>?;
          final type = map?['type'] as String?;
          switch (type) {
            case 'connection':
              final s = (map?['state'] as String?) ?? 'DISCONNECTED';
              final state = ConnectionState.values.firstWhere(
                (e) => e.name.toUpperCase() == s,
                orElse: () => ConnectionState.disconnected,
              );
              return BudTelemetryEvent(state: state);
            case 'battery':
              return BudTelemetryEvent(battery: BatterySnapshot.fromMap(map));
            case 'error':
              return BudTelemetryEvent(error: (map?['message'] as String?) ?? 'unknown error');
            case 'debug':
              return BudTelemetryEvent(debugLine: (map?['line'] as String?) ?? '');
            case 'noiseMode':
              return BudTelemetryEvent(noiseMode: (map?['value'] as num?)?.toInt());
            case 'gameMode':
              return BudTelemetryEvent(gameMode: map?['enabled'] as bool?);
            default:
              return const BudTelemetryEvent();
          }
        })
        .asBroadcastStream();
  }

  Future<bool> hasPermissions() async => (await _methods.invokeMethod<bool>('hasPermissions')) ?? false;

  Future<void> requestPermissions() => _methods.invokeMethod('requestPermissions');

  Future<bool> isBonded() async => (await _methods.invokeMethod<bool>('isBonded')) ?? false;

  Future<bool> pair() async => (await _methods.invokeMethod<bool>('pair')) ?? false;

  Future<bool> connect() async => (await _methods.invokeMethod<bool>('connect')) ?? false;

  Future<bool> disconnect() async => (await _methods.invokeMethod<bool>('disconnect')) ?? false;

  Future<BatterySnapshot> queryBattery() async => BatterySnapshot.fromMap(await _methods.invokeMethod('queryBattery'));

  Future<void> setNoiseMode(NoiseMode mode) =>
      _methods.invokeMethod('setNoiseMode', {'value': mode.value});

  /// ANC sub-level (Mild/Moderate/Deep) — ANC_CONFIG_SET type 0x14.
  Future<void> setAncCycleMode(int value) =>
      _methods.invokeMethod('setAncCycleMode', {'value': value});

  Future<void> setGameMode(bool on) =>
      _methods.invokeMethod('setGameMode', {'enabled': on});

  Future<void> setMultipoint(bool on) =>
      _methods.invokeMethod('setMultipoint', {'enabled': on});

  /// Make the buds play their locator tone for ~3 seconds.
  Future<void> findDevice() => _methods.invokeMethod('findDevice');

  /// Trigger the earbud fit-sweep command (MISC_CONFIG_SET, type 0x15).
  Future<void> triggerFitSweep() => _methods.invokeMethod('triggerFitSweep');

  /// Generic misc config write: [type, value] via MISC_CONFIG_SET.
  /// Used for EQ mode, spatial audio, volume enhancer, wind reduction, enhance
  /// voices, multipoint, game mode, fit sweep.
  Future<void> setMiscConfig(int type, int value) =>
      _methods.invokeMethod('setMiscConfig', {'type': type, 'value': value});

  /// Query fresh 1% battery and fire the Fast Pair battery broadcast with the
  /// precise values. Returns true when the broadcast was accepted.
  Future<bool> triggerBatteryPopup() async =>
      (await _methods.invokeMethod<bool>('triggerBatteryPopup')) ?? false;

  Future<void> startBatteryService() => _methods.invokeMethod('startBatteryService');

  Future<bool> getKeepAlive() async => (await _methods.invokeMethod<bool>('getKeepAlive')) ?? true;

  Future<void> setKeepAlive(bool value) => _methods.invokeMethod('setKeepAlive', value);
}
