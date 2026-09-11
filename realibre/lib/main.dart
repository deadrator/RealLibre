import 'package:flutter/material.dart' hide ConnectionState;
import 'package:dynamic_color/dynamic_color.dart';

import 'core/platform/method_channels.dart';
import 'state/bud_controller.dart';
import 'ui/screens/dashboard_screen.dart';
import 'ui/screens/pairing_screen.dart';
import 'ui/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RealiBreApp());
}

/// RealiBre — telemetry-free companion for the Realme Buds T310.
/// No analytics, no network: everything stays on-device over RFCOMM.
class RealiBreApp extends StatelessWidget {
  const RealiBreApp({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = BudController();
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return MaterialApp(
          title: 'RealiBre',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(lightDynamic),
          darkTheme: AppTheme.dark(darkDynamic),
          themeMode: ThemeMode.system,
          home: _Home(controller: controller),
        );
      },
    );
  }
}

class _Home extends StatefulWidget {
  const _Home({required this.controller});

  final BudController controller;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  /// Set when the user completes the manual pairing flow, so the dashboard
  /// shows immediately even before the CONNECTED event round-trips.
  bool _manuallyConnected = false;

  @override
  void initState() {
    super.initState();
    widget.controller.attach();
    widget.controller.addListener(_onControllerChanged);
    // Silent auto-connect: when the buds are already bonded (the normal case —
    // the phone is usually already streaming audio to them), open the control
    // channel straight away and land on the dashboard. No pairing screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.autoConnect();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (widget.controller.state == ConnectionState.disconnected ||
        widget.controller.state == ConnectionState.failed) {
      _manuallyConnected = false;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final inProgress = controller.state == ConnectionState.connecting ||
        controller.state == ConnectionState.authenticating;
    // Dashboard-first: show it while connected, while a (re)connect is in
    // flight, or right after a successful manual pairing. The pairing screen
    // is only for the never-paired and failed cases.
    final showDashboard = controller.isConnected ||
        _manuallyConnected ||
        (controller.autoConnectAttempted && inProgress);
    return showDashboard
        ? DashboardScreen(controller: controller)
        : PairingScreen(
            controller: controller,
            onConnected: () => setState(() => _manuallyConnected = true),
          );
  }
}
