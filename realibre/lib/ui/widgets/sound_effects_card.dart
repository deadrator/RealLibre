import 'package:flutter/material.dart';

import '../../core/constants/bud_enums.dart';
import '../../state/bud_controller.dart';

/// Sound effects card (realme Link style): EQ presets, Spatial Audio,
/// Volume enhancer, Dynamic audio, Enhance voices, Wind noise reduction.
///
/// The toggles are marked "not wired" — Realme Link exposes these features,
/// but their wire type bytes were rejected by the buds (MISC_CONFIG_ACK
/// status=0x01) and are not in the reverse-engineered protocol. Selection is
/// kept as local UI state only; nothing is sent over the wire.
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
            Text('Sound effects', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'Selection is remembered locally — wire commands for these are not discovered yet',
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            _EQModeTile(
              currentMode: controller.eqMode,
              onModeChanged: connected ? controller.setEQMode : null,
            ),
            const Divider(height: 1, indent: 44),
            _FeatureTile(
              icon: Icons.volume_up_rounded,
              label: 'Spatial Audio',
              subtitle: "Brand new 360° immersive surround sound experience, so you feel like you're right at the centre of the action.",
              value: controller.spatialAudio,
              onChanged: connected ? controller.setSpatialAudio : null,
            ),
            const Divider(height: 1, indent: 44),
            _FeatureTile(
              icon: Icons.graphic_eq_rounded,
              label: 'Volume enhancer',
              subtitle: 'Further increase the volume of your audio device.',
              value: controller.volumeEnhancer,
              onChanged: connected ? controller.setVolumeEnhancer : null,
            ),
            const Divider(height: 1, indent: 44),
            // The protocol has no known misc type for this on T310 yet;
            // shown disabled until a wire value is confirmed.
            const _FeatureTile(
              icon: Icons.auto_awesome_rounded,
              label: 'Dynamic audio',
              subtitle: 'Adaptive sound tuned to your environment.',
              value: false,
              onChanged: null,
            ),
            const Divider(height: 1, indent: 44),
            _FeatureTile(
              icon: Icons.person_2_rounded,
              label: 'Enhance voices',
              subtitle: 'Diminish ambient sounds and enhance voices.',
              value: controller.enhanceVoices,
              onChanged: connected ? controller.setEnhanceVoices : null,
            ),
            const Divider(height: 1, indent: 44),
            _FeatureTile(
              icon: Icons.air_rounded,
              label: 'Wind noise reduction',
              subtitle: 'Effectively reduce noises from the wind when the wind speed picks up.',
              value: controller.windNoiseReduction,
              onChanged: connected ? controller.setWindNoiseReduction : null,
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
                Text(label, style: theme.textTheme.bodyLarge),
                Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _EQModeTile extends StatelessWidget {
  const _EQModeTile({required this.currentMode, required this.onModeChanged});

  final EQMode currentMode;
  final ValueChanged<EQMode>? onModeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final connected = onModeChanged != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Icon(Icons.equalizer_rounded, size: 20, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('EQ mode', style: theme.textTheme.bodyLarge),
                Text(
                  currentMode.label,
                  style: theme.textTheme.bodySmall?.copyWith(color: accent, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: accent.withAlpha(26),
              borderRadius: BorderRadius.circular(20),
            ),
            child: IconButton(
              icon: const Icon(Icons.chevron_right_rounded, size: 20),
              onPressed: connected ? () => _showEQDialog(context) : null,
            ),
          ),
        ],
      ),
    );
  }

  void _showEQDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('EQ mode'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final EQMode mode in EQMode.values)
              ListTile(
                title: Text(mode.label),
                subtitle: Text(mode.subtitle),
                selected: currentMode == mode,
                onTap: () {
                  onModeChanged?.call(mode);
                  Navigator.of(dialogContext).pop();
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
