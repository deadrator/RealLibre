import 'package:flutter/material.dart';

import '../../core/constants/bud_enums.dart';
import '../theme/app_theme.dart';

/// Noise control card (realme Link style): three circular mode buttons, an
/// ANC sub-level row (Mild/Moderate/Deep) while ANC is active, and the two
/// transparency/ANC companion toggles.
class NoiseControlSelector extends StatelessWidget {
  const NoiseControlSelector({
    super.key,
    required this.mode,
    required this.ancCycleMode,
    required this.onModeChanged,
    required this.onCycleModeChanged,
    this.enabled = true,
  });

  final NoiseMode mode;
  final AncCycleMode ancCycleMode;
  final ValueChanged<NoiseMode> onModeChanged;
  final ValueChanged<AncCycleMode> onCycleModeChanged;
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
            Text(
              'ANC_CONFIG_SET · MODE',
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            _ModeButtonRow(
              mode: mode,
              accent: accent,
              onModeChanged: enabled ? onModeChanged : null,
            ),
            const SizedBox(height: 16),
            if (mode == NoiseMode.anc) ...[
              Text('Noise cancellation', style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text(
                ancCycleMode.subtitle,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final AncCycleMode level in AncCycleMode.values) ...[
                    _AncCycleChip(
                      label: level.label,
                      isSelected: ancCycleMode == level,
                      onTap: enabled ? () => onCycleModeChanged(level) : null,
                    ),
                    if (level != AncCycleMode.deep) const SizedBox(width: 8),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 14),
            _ToggleRow(
              icon: Icons.person_2_rounded,
              title: 'Enhance voices',
              subtitle: 'Diminish ambient sounds and enhance voices.',
              value: false,
              onChanged: null,
            ),
            _ToggleRow(
              icon: Icons.air_rounded,
              title: 'Wind noise reduction',
              subtitle: "Effectively reduce noises from the wind when the wind speed picks up. The earbud's noise cancellation feature will be affected.",
              value: false,
              onChanged: null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeButtonRow extends StatelessWidget {
  const _ModeButtonRow({
    required this.mode,
    required this.accent,
    required this.onModeChanged,
  });

  final NoiseMode mode;
  final Color accent;
  final ValueChanged<NoiseMode>? onModeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        for (final NoiseMode m in NoiseMode.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                children: [
                  InkWell(
                    onTap: onModeChanged != null ? () => onModeChanged!(m) : null,
                    borderRadius: BorderRadius.circular(28),
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: m == mode ? accent.withAlpha(51) : theme.colorScheme.surfaceContainerHighest.withAlpha(77),
                        border: Border.all(
                          color: m == mode ? accent : theme.colorScheme.outline.withAlpha(77),
                          width: m == mode ? 2 : 1,
                        ),
                      ),
                      child: Icon(
                        _iconFor(m),
                        size: 24,
                        color: m == mode ? accent : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    m.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: m == mode ? accent : theme.colorScheme.onSurfaceVariant,
                      fontWeight: m == mode ? FontWeight.w600 : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static IconData _iconFor(NoiseMode m) => switch (m) {
        NoiseMode.off => Icons.music_off_rounded,
        NoiseMode.anc => Icons.headphones_rounded,
        NoiseMode.transparency => Icons.hearing_rounded,
      };
}

class _AncCycleChip extends StatelessWidget {
  const _AncCycleChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? accent.withAlpha(26) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? accent : theme.colorScheme.outline.withAlpha(77),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? accent : theme.colorScheme.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyLarge),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
