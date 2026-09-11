import 'package:flutter/material.dart' hide ConnectionState;

import '../../core/platform/method_channels.dart';
import '../../state/bud_controller.dart';

/// Pairing + connect flow. Animates a pulsing earbud while searching, then
/// hands off to the dashboard once the HMAC handshake completes.
class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key, required this.controller, required this.onConnected});

  final BudController controller;
  final VoidCallback onConnected;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.controller.initialize();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _startFlow() async {
    widget.controller.clearError();
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.controller.pairAndConnect();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      widget.onConnected();
    } else {
      setState(() => _error = widget.controller.lastError ?? 'Could not reach the buds');
    }
  }

  /// Live phase label driven by the native connection state, so the user
  /// sees "Connecting…" vs "Authenticating…" instead of one static spinner.
  String get _busyLabel {
    switch (widget.controller.state) {
      case ConnectionState.connecting:
        return 'Connecting…';
      case ConnectionState.authenticating:
        return 'Authenticating…';
      default:
        return 'Working…';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          // Rebuild on controller changes: the label tracks the native phase
          // and errors reported over the event channel appear immediately.
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              final errorText = _error ?? widget.controller.lastError;
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Animated earbud with pulsing discovery rings.
                  SizedBox(
                    height: 220,
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, child) {
                        final t = _pulse.value;
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            for (final delay in [0.0, 0.33, 0.66])
                              if ((t + delay) % 1.0 < 0.6)
                                Container(
                                  width: 120 + ((t + delay) % 1.0) * 160,
                                  height: 120 + ((t + delay) % 1.0) * 160,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: theme.colorScheme.primary.withOpacity(
                                        0.35 * (1 - ((t + delay) % 1.0) / 0.6),
                                      ),
                                    ),
                                  ),
                                ),
                            child!,
                          ],
                        );
                      },
                      child: Container(
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.primary.withOpacity(0.15),
                        ),
                        child: Icon(Icons.headphones_rounded, size: 52, color: theme.colorScheme.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Realme Buds T310',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '88:0E:85:EF:12:24  •  Fast Pair 891148',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: _busy ? null : _startFlow,
                    icon: _busy
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.bluetooth_connected_rounded),
                    label: Text(_busy ? _busyLabel : 'Pair & connect'),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      errorText!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 40),
                  Text(
                    'Telemetry-free • fully local • open source',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
