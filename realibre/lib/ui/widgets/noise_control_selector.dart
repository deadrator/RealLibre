import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/bud_enums.dart';
import '../theme/app_theme.dart';

/// Three-state noise control selector (Off / ANC / Transparency).
/// Switching modes crossfades/slides the mode art at 350ms easeOutCubic and
/// fires a light haptic, mirroring the QS tile behavior.
class NoiseControlSelector extends StatelessWidget {
  const NoiseControlSelector({
    super.key,
    required this.mode,
    required this.onChanged,
    this.enabled = true,
  });

  final NoiseMode mode;
  final ValueChanged<NoiseMode> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.noiseAccent(mode);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Noise control', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('ANC_CONFIG_SET · MODE', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            // Animated mode art: crossfade + slide between the three modes.
            SizedBox(
              height: 56,
              width: double.infinity,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final slide = Tween<Offset>(begin: const Offset(0, 0.35), end: Offset.zero)
                      .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: slide, child: child),
                  );
                },
                child: _ModeArt(key: ValueKey(mode), mode: mode, accent: accent),
              ),
            ),
            const SizedBox(height: 14),
            SegmentedButton<NoiseMode>(
              segments: [
                for (final m in NoiseMode.values)
                  ButtonSegment(
                    value: m,
                    icon: Icon(_iconFor(m)),
                    label: Text(m.label),
                  ),
              ],
              selected: {mode},
              onSelectionChanged: enabled
                  ? (selection) {
                      HapticFeedback.selectionClick();
                      onChanged(selection.first);
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(NoiseMode m) => switch (m) {
        NoiseMode.off => Icons.music_off_rounded,
        NoiseMode.anc => Icons.headphones_rounded,
        NoiseMode.transparency => Icons.hearing_rounded,
      };
}

class _ModeArt extends StatelessWidget {
  const _ModeArt({super.key, required this.mode, required this.accent});

  final NoiseMode mode;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.85, end: 1.0),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: Icon(mode.icon, size: 36, color: accent)),
        ),
        const SizedBox(width: 12),
        Text(
          mode.subtitle,
          style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

extension on NoiseMode {
  IconData get icon => switch (this) {
        NoiseMode.off => Icons.music_off_rounded,
        NoiseMode.anc => Icons.headphones_rounded,
        NoiseMode.transparency => Icons.hearing_rounded,
      };
}
