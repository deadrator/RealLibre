import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/bud_enums.dart';
import '../../state/bud_controller.dart';

/// Sound & effects card: EQ presets plus every Attr 0x04 boolean toggle.
/// Each switch gives haptic feedback and animates on state change.
class SoundEffectsCard extends StatelessWidget {
  const SoundEffectsCard({super.key, required this.controller});

  final BudController controller;

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
            Text('Sound & effects', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Cmd 0x04 ATTR_SET', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            // EQ selector
            SizedBox(
              width: double.infinity,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final eq in EqMode.values)
                    ChoiceChip(
                      label: Text(eq.label),
                      selected: controller.eqMode == eq,
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        controller.setEqMode(eq);
                      },
                    ),
                ],
              ),
            ),
            const Divider(height: 24),
            _SwitchTile(
              icon: Icons.videogame_asset_rounded,
              label: 'Gaming mode',
              subtitle: 'Low latency (0x06)',
              value: controller.isToggleOn('gaming'),
              onChanged: (v) => controller.setToggle('gaming', v),
            ),
            _SwitchTile(
              icon: Icons.view_in_ar_rounded,
              label: 'Spatial audio (360°)',
              subtitle: 'Head tracking soundstage (0x10)',
              value: controller.isToggleOn('spatial'),
              onChanged: (v) => controller.setToggle('spatial', v),
            ),
            _SwitchTile(
              icon: Icons.volume_up_rounded,
              label: 'Volume enhancer',
              subtitle: 'Gain boost (0x0E)',
              value: controller.isToggleOn('volumeEnhancer'),
              onChanged: (v) => controller.setToggle('volumeEnhancer', v),
            ),
            _SwitchTile(
              icon: Icons.air_rounded,
              label: 'Wind noise reduction',
              subtitle: 'Outdoor calls (0x12)',
              value: controller.isToggleOn('windNoise'),
              onChanged: (v) => controller.setToggle('windNoise', v),
            ),
            _SwitchTile(
              icon: Icons.record_voice_over_rounded,
              label: 'Enhance voices',
              subtitle: 'Transparency sub-option (0x13)',
              value: controller.isToggleOn('enhanceVoices'),
              onChanged: (v) => controller.setToggle('enhanceVoices', v),
            ),
            _SwitchTile(
              icon: Icons.phonelink_ring_rounded,
              label: 'Multipoint',
              subtitle: 'Dual device connection (0x09)',
              value: controller.isToggleOn('multipoint'),
              onChanged: (v) => controller.setToggle('multipoint', v),
            ),
            _SwitchTile(
              icon: Icons.checkroom_rounded,
              label: 'Fit sweep test',
              subtitle: 'One-shot tone sweep (0x15)',
              value: false,
              onChanged: (_) => controller.setToggle('fitTest', true),
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
  final ValueChanged<bool> onChanged;

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
            onChanged(v);
          }),
        ],
      ),
    );
  }
}
