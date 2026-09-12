import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';
import 'package:realibre/core/constants/bud_enums.dart';
import 'package:realibre/core/platform/method_channels.dart';
import 'package:realibre/models/bud_telemetry.dart';
import 'package:realibre/state/bud_controller.dart';
import 'package:realibre/ui/screens/dashboard_screen.dart';
import 'package:realibre/ui/screens/pairing_screen.dart';
import 'package:realibre/ui/theme/app_theme.dart';

/// Stub channel bridge for widget tests: no native side exists in the test
/// environment, so every method call resolves to a safe default.
class _StubChannels implements BudChannels {
  @override
  Future<bool> getKeepAlive() async => true;

  @override
  Future<bool> hasPermissions() async => true;

  @override
  Stream<BudTelemetryEvent> events() => const Stream<BudTelemetryEvent>.empty();

  @override
  Future<bool> triggerBatteryPopup() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BudTelemetry model', () {
    test('parses map and flags coarse sources', () {
      final t = BudTelemetry.fromMap(const {
        'left': 81,
        'right': 66,
        'case': 42,
        'source': 'hfp',
      });
      expect(t.left, 81);
      expect(t.right, 66);
      expect(t.caseLevel, 42);
      expect(t.isCoarse, isTrue);

      final rf = BudTelemetry.fromMap(const {'left': 1, 'right': 2, 'case': 3});
      expect(rf.isCoarse, isFalse);
    });

    test('seed values are realistic', () {
      expect(BudTelemetry.seed.left, inInclusiveRange(0, 100));
      expect(BudTelemetry.seed.source, 'rfcomm');
    });
  });

  group('bud enums (real Oppo/Realme protocol values)', () {
    test('noise mode wire values match the real protocol', () {
      // 0x01=off, 0x02=transparency, 0x08=ANC — NOT the 0/1/2 from the old spec.
      expect(NoiseMode.off.value, 0x01);
      expect(NoiseMode.transparency.value, 0x02);
      expect(NoiseMode.anc.value, 0x08);
      expect(NoiseMode.fromValue(8), NoiseMode.anc);
      expect(NoiseMode.fromValue(2), NoiseMode.transparency);
      expect(NoiseMode.fromValue(1), NoiseMode.off);
    });

    test('unknown values fall back to off, not throw', () {
      expect(NoiseMode.fromValue(0x99), NoiseMode.off);
    });

    test('ANC cycle mode values', () {
      expect(AncCycleMode.mild.value, 0x00);
      expect(AncCycleMode.moderate.value, 0x01);
      expect(AncCycleMode.deep.value, 0x02);
    });

    test('game + multipoint flags', () {
      expect(GameMode.on.value, 0x01);
      expect(MultipointMode.on.value, 0x01);
    });

    test('EQ mode values', () {
      expect(EQMode.default_.value, 0x00);
      expect(EQMode.bassBoost.value, 0x01);
      expect(EQMode.clearBass.value, 0x02);
      expect(EQMode.clearVocals.value, 0x03);
    });

    test('undiscovered features keep display values for UI parity', () {
      // These features exist in Realme Link but their wire types are not
      // discovered; values here are display-only and never sent.
      expect(SpatialAudio.on.value, 0x01);
      expect(VolumeEnhancer.on.value, 0x01);
      expect(EnhanceVoices.on.value, 0x01);
      expect(WindNoiseReduction.on.value, 0x01);
      expect(EQMode.clearBass.value, 0x02);
    });
  });

  group('theme', () {
    test('noise accent maps all modes', () {
      for (final m in NoiseMode.values) {
        expect(AppTheme.noiseAccent(m), isA<Color>());
      }
    });
  });

  group('widgets', () {
    testWidgets('dashboard renders status bar', (tester) async {
      budChannelsInstance = _StubChannels();
      final controller = BudController(channels: _StubChannels());
      await tester.pumpWidget(
        MaterialApp(home: DashboardScreen(controller: controller)),
      );
      expect(find.text('Realme Buds T310'), findsOneWidget);
    });

    testWidgets('pairing screen renders device info', (tester) async {
      budChannelsInstance = _StubChannels();
      final controller = BudController(channels: _StubChannels());
      await tester.pumpWidget(
        MaterialApp(home: PairingScreen(controller: controller, onConnected: () {})),
      );
      expect(find.text('Realme Buds T310'), findsOneWidget);
      expect(find.text('Pair & connect'), findsOneWidget);
    });
  });
}
