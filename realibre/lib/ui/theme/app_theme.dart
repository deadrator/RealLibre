import 'package:flutter/material.dart';

import '../../core/constants/bud_enums.dart';

/// Material 3 theme with dynamic color (Android 12+) and a dark
/// "midnight driver" fallback palette tuned for a buds companion app.
class AppTheme {
  AppTheme._();

  static ThemeData light(ColorScheme? dynamic) =>
      _base(dynamic ?? ThemeData(useMaterial3: true).colorScheme, Brightness.light);

  static ThemeData dark(ColorScheme? dynamic) =>
      _base(dynamic ?? _darkScheme, Brightness.dark);

  static const ColorScheme _darkScheme = ColorScheme.dark(
    primary: Color(0xFF7F67BE),
    onPrimary: Color(0xFF1E1A2E),
    secondary: Color(0xFF62DDB9),
    onSecondary: Color(0xFF00201A),
    tertiary: Color(0xFFEFB8C8),
    surface: Color(0xFF15121E),
    onSurface: Color(0xFFE8E1F0),
    surfaceContainerHighest: Color(0xFF241F31),
    outline: Color(0xFF4A4458),
  );

  static ThemeData _base(ColorScheme scheme, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? const Color(0xFF0E0C14) : null,
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  /// Noise mode → semantic accent, used by tile + selector + notification.
  static Color noiseAccent(NoiseMode mode) => switch (mode) {
        NoiseMode.anc => const Color(0xFF7F67BE),
        NoiseMode.transparency => const Color(0xFF62DDB9),
        NoiseMode.off => const Color(0xFF9E9AA7),
      };
}
