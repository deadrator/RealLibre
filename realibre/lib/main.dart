import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';

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
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    widget.controller.attach();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  /// A dropped socket flips the controller state back to disconnected —
  /// return to the pairing screen instead of freezing on a dead dashboard.
  void _onControllerChanged() {
    final connected = widget.controller.isConnected;
    if (!mounted || connected == _connected) return;
    setState(() => _connected = connected);
  }

  @override
  Widget build(BuildContext context) {
    return _connected
        ? DashboardScreen(controller: widget.controller)
        : PairingScreen(
            controller: widget.controller,
            onConnected: () => setState(() => _connected = true),
          );
  }
}
