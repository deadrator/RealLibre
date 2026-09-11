import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/bud_controller.dart';

/// Device features card: the toggles the real protocol actually supports
/// (game mode, multipoint) plus the find-my-buds tone.
class SoundEffectsCard extends StatelessWidget {
  const SoundEffectsCard({super.key, required this.controller});

  final BudController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = controller.isConnected;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Device features', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Oppo/Realme protocol — misc config', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            _SwitchTile(
              icon: Icons.videogame_asset_rounded,
              label: 'Game mode',
              subtitle: 'Low latency audio',
              value: controller.gameMode,
              onChanged: connected ? (v) => controller.setGameMode(v) : null,
            ),
            _SwitchTile(
              icon: Icons.phonelink_ring_rounded,
              label: 'Multipoint',
              subtitle: 'Dual device connection',
              value: controller.multipoint,
              onChanged: connected ? (v) => controller.setMultipoint(v) : null,
            ),
            _SwitchTile(
              icon: Icons.location_searching_rounded,
              label: 'Find my buds',
              subtitle: 'Play locator tone',
              value: false,
              onChanged: connected ? (_) => controller.findDevice() : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: value
                  ? theme.colorScheme.primary.withOpacity(0.18)
                  : theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 22, color: value ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyLarge),
                Text(subtitle, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          Switch(value: value, onChanged: (v) {
            HapticFeedback.lightImpact();
            onChanged?.call(v);
          }),
        ],
      ),
    );
  }
}
