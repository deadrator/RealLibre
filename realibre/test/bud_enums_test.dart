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
      final t = BudTelemetry.fromMap({
        'left': 81,
        'right': 66,
        'case': 42,
        'source': 'hfp',
      });
      expect(t.left, 81);
      expect(t.right, 66);
      expect(t.caseLevel, 42);
      expect(t.isCoarse, isTrue);

      final rf = BudTelemetry.fromMap({'left': 1, 'right': 2, 'case': 3});
      expect(rf.isCoarse, isFalse);
    });

    test('seed values are realistic', () {
      expect(BudTelemetry.seed.left, inInclusiveRange(0, 100));
      expect(BudTelemetry.seed.source, 'rfcomm');
    });
  });

  group('bud enums', () {
    test('noise mode wire values match protocol spec', () {
      expect(NoiseMode.off.value, 0x00);
      expect(NoiseMode.anc.value, 0x01);
      expect(NoiseMode.transparency.value, 0x02);
      expect(NoiseMode.fromValue(2), NoiseMode.transparency);
    });

    test('EQ mode wire values match protocol spec', () {
      expect(EqMode.defaultMode.value, 0x00);
      expect(EqMode.bassBoost.value, 0x01);
      expect(EqMode.clearBass.value, 0x02);
      expect(EqMode.clearVocals.value, 0x03);
    });

    test('attribute IDs match ProtocolConstants.kt table', () {
      expect(AttrId.noiseControl, 0x05);
      expect(AttrId.gaming, 0x06);
      expect(AttrId.multipoint, 0x09);
      expect(AttrId.eqMode, 0x0A);
      expect(AttrId.volumeEnhancer, 0x0E);
      expect(AttrId.spatialAudio, 0x10);
      expect(AttrId.windNoise, 0x12);
      expect(AttrId.enhanceVoices, 0x13);
      expect(AttrId.ancSubLevel, 0x14);
      expect(AttrId.fitTest, 0x15);
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
    testWidgets('dashboard renders compact status bar with battery', (tester) async {
      budChannelsInstance = _StubChannels();
      final controller = BudController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(null),
          home: DashboardScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Realme Buds T310'), findsOneWidget);
      expect(find.text('Battery'), findsNothing); // settings collapsed by default
      expect(find.byType(DashboardScreen), findsOneWidget);
    });

    testWidgets('pairing screen shows device info and CTA', (tester) async {
      budChannelsInstance = _StubChannels();
      final controller = BudController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(null),
          home: PairingScreen(controller: controller, onConnected: () {}),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Realme Buds T310'), findsOneWidget);
      expect(find.text('Pair & connect'), findsOneWidget);
    });
  });
}
