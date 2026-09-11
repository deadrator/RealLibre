import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';

import '../../core/platform/method_channels.dart';
import '../../state/bud_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/noise_control_selector.dart';
import '../widgets/sound_effects_card.dart';

/// Dashboard: a compact earbud status bar pinned at ~1/4 of screen height
/// showing live ANC mode + battery; tapping it expands the full settings
/// sheet below with an animated crossfade.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.controller});

  final BudController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        return Scaffold(
          appBar: AppBar(
            title: const Text('RealiBre'),
            backgroundColor: Colors.transparent,
            actions: [
              _ConnectionBadge(state: state),
              IconButton(
                tooltip: 'Disconnect',
                icon: const Icon(Icons.bluetooth_disabled_rounded),
                onPressed: controller.disconnect,
              ),
            ],
          ),
          body: SafeArea(
            child: _DashboardBody(controller: controller, state: state),
          ),
        );
      },
    );
  }
}

class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({required this.state});

  final ConnectionState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (state) {
      ConnectionState.connected => ('Connected', theme.colorScheme.secondary),
      ConnectionState.connecting => ('Connecting…', theme.colorScheme.tertiary),
      ConnectionState.authenticating => ('Authenticating…', theme.colorScheme.tertiary),
      ConnectionState.failed => ('Failed', theme.colorScheme.error),
      ConnectionState.disconnected => ('Offline', theme.colorScheme.onSurfaceVariant),
    };
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Chip(
        label: Text(label, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface)),
        avatar: CircleAvatar(backgroundColor: color, radius: 4),
        visualDensity: VisualDensity.compact,
        backgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.6),
        side: BorderSide.none,
      ),
    );
  }
}

class _DashboardBody extends StatefulWidget {
  const _DashboardBody({required this.controller, required this.state});

  final BudController controller;
  final ConnectionState state;

  @override
  State<_DashboardBody> createState() => _DashboardBodyState();
}

class _DashboardBodyState extends State<_DashboardBody> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final connected = widget.state == ConnectionState.connected;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              children: [
                // ── The 1/4-screen status bar ──────────────────────────
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _expanded = !_expanded);
                  },
                  child: _BudStatusBar(
                    height: size.height * 0.25,
                    controller: controller,
                    expanded: _expanded,
                  ),
                ),
                // ── Expandable settings ────────────────────────────────
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 400),
                  sizeCurve: Curves.easeOutCubic,
                  crossFadeState:
                      _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  firstChild: const SizedBox(width: double.infinity),
                  secondChild: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: Column(
                      children: [
                        NoiseControlSelector(
                          mode: controller.noiseMode,
                          onChanged: controller.setNoiseMode,
                          enabled: connected,
                        ),
                        const SizedBox(height: 12),
                        SoundEffectsCard(controller: controller),
                        const SizedBox(height: 12),
                        // Keep alive in background
                        Card(
                          margin: EdgeInsets.zero,
                          child: SwitchListTile(
                            title: const Text('Keep connection in background'),
                            subtitle: const Text('Stay paired when the app is hidden'),
                            value: controller.keepAlive,
                            onChanged: connected ? controller.setKeepAlive : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!_expanded)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24, top: 8),
                    child: Text(
                      'Tap the bar for noise, EQ & effects',
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The compact rectangular bar: earbud art + current ANC mode + mini battery.
class _BudStatusBar extends StatelessWidget {
  const _BudStatusBar({
    required this.height,
    required this.controller,
    required this.expanded,
  });

  final double height;
  final BudController controller;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final battery = controller.battery;
    final mode = controller.noiseMode;
    final accent = AppTheme.noiseAccent(mode);
    final connected = controller.isConnected;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      height: height,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withOpacity(connected ? 0.22 : 0.08),
            theme.colorScheme.surfaceContainerHighest.withOpacity(0.6),
          ],
        ),
        border: Border.all(color: accent.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          // Earbud art with connection-state animation.
          AnimatedRotation(
            turns: connected ? 0 : 0.12,
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            child: AnimatedScale(
              scale: connected ? 1.0 : 0.9,
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withOpacity(0.2),
                  border: Border.all(color: accent, width: 1.5),
                ),
                child: Icon(
                  Icons.headphones_rounded,
                  size: 30,
                  color: connected ? accent : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Realme Buds T310',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOutCubic,
                  child: Text(
                    connected ? '${mode.label} mode' : 'Tap to reconnect in settings',
                    key: ValueKey(connected ? mode.label : 'offline'),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          // Mini battery pills.
          _MiniBattery(label: 'L', value: battery.left, accent: accent),
          const SizedBox(width: 8),
          _MiniBattery(label: 'R', value: battery.right, accent: accent),
          const SizedBox(width: 8),
          _MiniBattery(label: 'C', value: battery.caseLevel, accent: theme.colorScheme.primary),
          const SizedBox(width: 6),
          AnimatedRotation(
            turns: expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            child: Icon(Icons.keyboard_arrow_down_rounded, color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _MiniBattery extends StatelessWidget {
  const _MiniBattery({required this.label, required this.value, required this.accent});

  final String label;
  final int value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 30,
          height: 34,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Container(
                width: 22,
                height: 30,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: accent.withOpacity(0.6)),
                ),
                alignment: Alignment.bottomCenter,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(5)),
                  child: AnimatedFractionallySizedBox(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    heightFactor: value.clamp(0, 100) / 100,
                    alignment: Alignment.bottomCenter,
                    child: ColoredBox(color: accent),
                  ),
                ),
              ),
              Text(
                '$value',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  color: value > 35 ? Colors.white : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: theme.textTheme.labelSmall?.copyWith(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
