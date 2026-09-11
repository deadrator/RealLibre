/// Typed wrapper over the `realibre/methods` + `realibre/events` platform
/// channels. All bud writes funnel through here and end up in the framed,
/// HMAC-authenticated native path.
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
  const BudTelemetryEvent({this.battery, this.error, this.state});
  final BatterySnapshot? battery;
  final String? error;
  final ConnectionState? state;
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
      _methods.invokeMethod('setAttribute', {'attr': AttrId.noiseControl, 'value': mode.value});

  Future<void> setAncLevel(AncLevel level) =>
      _methods.invokeMethod('setAttribute', {'attr': AttrId.ancSubLevel, 'value': level.value});

  Future<void> setEqMode(EqMode mode) =>
      _methods.invokeMethod('setAttribute', {'attr': AttrId.eqMode, 'value': mode.value});

  Future<void> setGaming(bool on) =>
      _methods.invokeMethod('setAttribute', {'attr': AttrId.gaming, 'value': on ? 1 : 0});

  Future<void> setSpatialAudio(bool on) =>
      _methods.invokeMethod('setAttribute', {'attr': AttrId.spatialAudio, 'value': on ? 1 : 0});

  Future<void> setVolumeEnhancer(bool on) =>
      _methods.invokeMethod('setAttribute', {'attr': AttrId.volumeEnhancer, 'value': on ? 1 : 0});

  Future<void> setWindNoise(bool on) =>
      _methods.invokeMethod('setAttribute', {'attr': AttrId.windNoise, 'value': on ? 1 : 0});

  Future<void> setEnhanceVoices(bool on) =>
      _methods.invokeMethod('setAttribute', {'attr': AttrId.enhanceVoices, 'value': on ? 1 : 0});

  Future<void> setMultipoint(bool on) =>
      _methods.invokeMethod('setAttribute', {'attr': AttrId.multipoint, 'value': on ? 1 : 0});

  Future<void> triggerFitTest() =>
      _methods.invokeMethod('setAttribute', {'attr': AttrId.fitTest, 'value': 1});

  /// Query fresh 1% battery and fire the Fast Pair battery broadcast with the
  /// precise values. Returns true when the broadcast was accepted.
  Future<bool> triggerBatteryPopup() async =>
      (await _methods.invokeMethod<bool>('triggerBatteryPopup')) ?? false;

  Future<void> startBatteryService() => _methods.invokeMethod('startBatteryService');

  Future<bool> getKeepAlive() async => (await _methods.invokeMethod<bool>('getKeepAlive')) ?? true;

  Future<void> setKeepAlive(bool value) => _methods.invokeMethod('setKeepAlive', value);
}
