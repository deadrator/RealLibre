import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/bud_enums.dart';
import '../../state/bud_controller.dart';

/// Sound effects card matching realme Link app layout.
/// Contains EQ mode, Spatial Audio, Volume enhancer, Dynamic audio.
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
            const SizedBox(height: 12),
            // EQ mode
            _EQModeTile(
              currentMode: controller.eqMode,
              onModeChanged: connected ? controller.setEQMode : null,
            ),
            const Divider(height: 1, color: Colors.divider, indent: 44),
            // Spatial Audio
            _FeatureTile(
              icon: Icons.volume_up_rounded,
              label: 'Spatial Audio',
              subtitle: 'Brand new 360° immersive surround sound experience, so you feel like you\'re right at the centre of the action.',
              value: controller.spatialAudio,
              onChanged: connected ? (v) => controller.setSpatialAudio(v) : null,
            ),
            const Divider(height: 1, color: Colors.divider, indent: 44),
            // Volume enhancer
            _FeatureTile(
              icon: Icons.graphic_eq_rounded,
              label: 'Volume enhancer',
              subtitle: 'Further increase the volume of your audio device.',
              value: controller.volumeEnhancer,
              onChanged: connected ? (v) => controller.setVolumeEnhancer(v) : null,
            ),
            const Divider(height: 1, color: Colors.divider, indent: 44),
            // Dynamic audio
            _FeatureTile(
              icon: Icons.graphic_eq_rounded,
              label: 'Dynamic audio',
              subtitle: 'Adaptive sound based on your environment.',
              value: false,
              onChanged: null,
            ),
            const Divider(height: 1, color: Colors.divider, indent: 44),
            // Enhance voices
            _FeatureTile(
              icon: Icons.person_2_rounded,
              label: 'Enhance voices',
              subtitle: 'Diminish ambient sounds and enhance voices.',
              value: controller.enhanceVoices,
              onChanged: connected ? (v) => controller.setEnhanceVoices(v) : null,
            ),
            const Divider(height: 1, color: Colors.divider, indent: 44),
            // Wind noise reduction
            _FeatureTile(
              icon: Icons.air_rounded,
              label: 'Wind noise reduction',
              subtitle: 'Effectively reduce noises from the wind when the wind speed picks up.',
              value: controller.windNoiseReduction,
              onChanged: connected ? (v) => controller.setWindNoiseReduction(v) : null,
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
          Switch(
            value: value,
            onChanged: onChanged,
          ),
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
                Text(currentMode.label, style: theme.textTheme.bodySmall?.copyWith(color: Colors.blue)),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
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
      builder: (context) => AlertDialog(
        title: const Text('EQ Mode'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: EQMode.values.map((mode) => ListTile(
            title: Text(mode.label),
            subtitle: Text(mode.subtitle),
            selected: currentMode == mode,
            onTap: () {
              onModeChanged?.call(mode);
              Navigator.of(context).pop();
            },
          )).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
