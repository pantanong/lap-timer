import 'package:lap_timer/theme/app_colors.dart';
import 'package:material_ui/material_ui.dart';

/// Builds the app's single (dark) theme from [AppColors].
abstract final class AppTheme {
  /// Dark theme used everywhere, including while driving.
  static ThemeData dark() {
    const c = AppColors.dark;
    final scheme = const ColorScheme.dark().copyWith(
      primary: c.accent,
      onPrimary: const Color(0xFF00201B),
      surface: c.surface,
      onSurface: c.textPrimary,
      outline: c.outline,
      error: c.slower,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      extensions: const [c],
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.textPrimary,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.outline),
        ),
      ),
    );
  }

  /// Monospaced-width digits so running times do not jitter sideways.
  static const List<FontFeature> tabularFigures = [
    FontFeature.tabularFigures(),
  ];
}
