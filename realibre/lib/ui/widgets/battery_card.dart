import 'package:flutter/material.dart';

import '../../models/bud_telemetry.dart';

/// Animated card with liquid-style battery fills per side (L/R/Case).
/// Uses implicit animations so fills glide at 400ms easeOutCubic on every
/// telemetry update.
class BatteryCard extends StatelessWidget {
  const BatteryCard({
    super.key,
    required this.telemetry,
    this.onRefresh,
    this.onPopup,
  });

  final BudTelemetry telemetry;
  final VoidCallback? onRefresh;
  final VoidCallback? onPopup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.battery_charging_full_rounded, size: 20, color: accent),
                const SizedBox(width: 8),
                Text('Battery', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                if (telemetry.isCoarse)
                  Tooltip(
                    message: 'HFP fallback: coarse 10% steps',
                    child: Chip(
                      label: const Text('coarse', style: TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: accent.withAlpha(38),
                      side: BorderSide.none,
                    ),
                  ),
                if (onRefresh != null)
                  IconButton(
                    tooltip: 'Poll buds (Cmd 0x03)',
                    visualDensity: VisualDensity.compact,
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _Cell(label: 'Left', value: telemetry.left, accent: accent)),
                const SizedBox(width: 12),
                Expanded(child: _Cell(label: 'Right', value: telemetry.right, accent: accent)),
                const SizedBox(width: 12),
                Expanded(
                  child: _Cell(
                    label: 'Case',
                    value: telemetry.caseLevel,
                    accent: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            if (onPopup != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onPopup,
                  icon: const Icon(Icons.bolt_rounded),
                  label: const Text('Force Fast Pair battery popup'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value, required this.accent});

  final String label;
  final int value;
  final Color accent;

  static const _animDuration = Duration(milliseconds: 400);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 64,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(color: theme.colorScheme.surfaceContainerHighest.withAlpha(153)),
                ),
                // Liquid-style animated fill from the bottom.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: AnimatedFractionallySizedBox(
                    duration: _animDuration,
                    curve: Curves.easeOutCubic,
                    heightFactor: (value.clamp(0, 100)) / 100,
                    alignment: Alignment.bottomCenter,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [accent, accent.withAlpha(140)],
                        ),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    '$value%',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: value > 30 ? Colors.white : null,
                      shadows: const [Shadow(blurRadius: 8, color: Colors.black38)],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
