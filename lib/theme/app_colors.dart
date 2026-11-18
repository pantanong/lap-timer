import 'package:material_ui/material_ui.dart';

/// Semantic colours used across the app, read with `AppColors.of(context)`.
///
/// Widgets never use raw colour values: they ask for a role ("faster",
/// "slower", "personal best") so the whole palette can change in one place.
/// The app is dark-first because dark screens glare less in a car.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  /// Creates the colour set. Use [dark] for the app palette.
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.outline,
    required this.textPrimary,
    required this.textMuted,
    required this.accent,
    required this.faster,
    required this.slower,
    required this.personalBest,
    required this.warning,
  });

  /// The app's dark palette.
  static const AppColors dark = AppColors(
    background: Color(0xFF0B0D10),
    surface: Color(0xFF151920),
    surfaceRaised: Color(0xFF1E242D),
    outline: Color(0xFF2A313C),
    textPrimary: Color(0xFFF2F4F7),
    textMuted: Color(0xFF8A94A3),
    accent: Color(0xFF00D1B2),
    faster: Color(0xFF22C55E),
    slower: Color(0xFFEF4444),
    personalBest: Color(0xFFA855F7),
    warning: Color(0xFFFACC15),
  );

  /// Screen background.
  final Color background;

  /// Cards and panels.
  final Color surface;

  /// Elevated controls on top of [surface].
  final Color surfaceRaised;

  /// Borders and dividers.
  final Color outline;

  /// Main text.
  final Color textPrimary;

  /// Labels and secondary text.
  final Color textMuted;

  /// Brand / primary action colour.
  final Color accent;

  /// Time gained (negative delta), speed within limit.
  final Color faster;

  /// Time lost (positive delta), over the limit, "brake now".
  final Color slower;

  /// Best lap / best sector of the session.
  final Color personalBest;

  /// Approaching a limit or a brake point.
  final Color warning;

  /// Reads the palette from the nearest theme.
  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? dark;

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? outline,
    Color? textPrimary,
    Color? textMuted,
    Color? accent,
    Color? faster,
    Color? slower,
    Color? personalBest,
    Color? warning,
  }) => AppColors(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    outline: outline ?? this.outline,
    textPrimary: textPrimary ?? this.textPrimary,
    textMuted: textMuted ?? this.textMuted,
    accent: accent ?? this.accent,
    faster: faster ?? this.faster,
    slower: slower ?? this.slower,
    personalBest: personalBest ?? this.personalBest,
    warning: warning ?? this.warning,
  );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      faster: Color.lerp(faster, other.faster, t)!,
      slower: Color.lerp(slower, other.slower, t)!,
      personalBest: Color.lerp(personalBest, other.personalBest, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}
