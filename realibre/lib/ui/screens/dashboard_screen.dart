import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';

import '../../core/constants/bud_enums.dart';
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
        final connected = state == ConnectionState.connected;
        return Scaffold(
          appBar: AppBar(
            title: const Text('RealiBre'),
            backgroundColor: Colors.transparent,
            actions: [
              _ConnectionBadge(state: state),
              IconButton(
                tooltip: 'Debug log',
                icon: const Icon(Icons.bug_report_outlined),
                onPressed: () => _showDebugLog(context, controller),
              ),
              if (!connected)
                IconButton(
                  tooltip: 'Reconnect',
                  icon: const Icon(Icons.bluetooth_searching_rounded),
                  onPressed: controller.reconnect,
                ),
              if (connected)
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

  /// Live wire log from the native stack: every frame sent/received (hex),
  /// every dial attempt and handshake step. This is how we find out whether
  /// the documented protocol actually matches the real buds.
  void _showDebugLog(BuildContext context, BudController controller) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return AnimatedBuilder(
          animation: controller,
          builder: (context, _) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            maxChildSize: 0.9,
            builder: (context, scrollController) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      Icon(Icons.terminal_rounded, size: 18, color: Theme.of(sheetContext).colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Wire debug — RFCOMM frames',
                          style: Theme.of(sheetContext).textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                ),
                if (controller.lastError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      controller.lastError!,
                      style: Theme.of(sheetContext)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Theme.of(sheetContext).colorScheme.error),
                    ),
                  ),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(sheetContext).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: controller.debugLines.isEmpty
                        ? Center(
                            child: Text(
                              'No wire traffic yet — reconnect to capture frames',
                              style: Theme.of(sheetContext).textTheme.bodySmall,
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: controller.debugLines.length,
                            itemBuilder: (context, i) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: SelectableText(
                                controller.debugLines[i],
                                style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                                      fontFamily: 'monospace',
                                      height: 1.3,
                                    ),
                              ),
                            ),
                          ),
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
                    if (!connected) {
                      controller.reconnect();
                      return;
                    }
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
                  secondChild: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      child: Column(
                        children: [
                          // Noise control card
                          NoiseControlSelector(
                            mode: controller.noiseMode,
                            ancCycleMode: controller.ancCycleMode,
                            onModeChanged: controller.setNoiseMode,
                            onCycleModeChanged: controller.setAncCycleMode,
                            enabled: connected,
                          ),
                          const SizedBox(height: 12),
                          // Sound effects card
                          SoundEffectsCard(controller: controller),
                          const SizedBox(height: 12),
                          // Device features card
                          _DeviceFeaturesCard(controller: controller, connected: connected),
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

/// Device features card matching realme Link app layout.
class _DeviceFeaturesCard extends StatelessWidget {
  const _DeviceFeaturesCard({required this.controller, required this.connected});

  final BudController controller;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Device features', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            // Dual-device connection (Multipoint)
            _FeatureTile(
              icon: Icons.phonelink_circle_rounded,
              title: 'Dual-device connection',
              subtitle: 'Connect 2 devices at the same time and switch between them easily.',
              value: controller.multipoint,
              onChanged: connected ? (v) => controller.setMultipoint(v) : null,
            ),
            const Divider(height: 1, color: Colors.divider, indent: 44),
            // Game mode
            _FeatureTile(
              icon: Icons.videogame_asset_rounded,
              title: 'Game mode',
              subtitle: 'Provides a seamless gaming experience with reduced latency.',
              value: controller.gameMode,
              onChanged: connected ? (v) => controller.setGameMode(v) : null,
            ),
            const Divider(height: 1, color: Colors.divider, indent: 44),
            // Earbud fit test
            _ActionTile(
              icon: Icons.menu_open_rounded,
              title: 'Earbud fit test',
              subtitle: 'Choose ear tips that make a good seal with your ear canals.',
              onTap: connected ? controller.triggerFitSweep : null,
            ),
            const Divider(height: 1, color: Colors.divider, indent: 44),
            // Find my buds
            _ActionTile(
              icon: Icons.location_searching_rounded,
              title: 'Find my buds',
              subtitle: 'Play locator tone to find your earbuds.',
              onTap: connected ? controller.findDevice : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyLarge),
                Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyLarge),
                Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
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
                    connected ? '${mode.label} mode' : 'Tap to reconnect',
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
