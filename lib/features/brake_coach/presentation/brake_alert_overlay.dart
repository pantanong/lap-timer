import 'package:lap_timer/features/brake_coach/domain/brake_alert.dart';
import 'package:lap_timer/l10n/generated/app_localizations.dart';
import 'package:lap_timer/theme/app_colors.dart';
import 'package:lap_timer/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

/// Full-screen brake alert (mockups 3 and 4): the whole screen turns
/// yellow ("get ready", with the distance left) and then red ("BRAKE"), so
/// it is visible from the corner of the eye without reading anything.
class BrakeAlertOverlay extends StatelessWidget {
  /// Shows [alert]; renders nothing when there is no alert.
  const BrakeAlertOverlay({required this.alert, super.key});

  /// The alert to show.
  final BrakeAlert alert;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    final corner = (alert.cornerIndex ?? 0) + 1;
    return switch (alert.phase) {
      BrakeAlertPhase.none => const SizedBox.shrink(),
      BrakeAlertPhase.approaching => _FullScreen(
        background: colors.warning,
        foreground: const Color(0xFF1A1400),
        corner: l10n.brakeCorner(corner),
        title: l10n.brakeGetReady,
        subtitle: switch (alert.metresToBrakePoint) {
          final m? => l10n.unitMetres(m.clamp(0, 999).toStringAsFixed(0)),
          null => null,
        },
      ),
      BrakeAlertPhase.brakeNow => _FullScreen(
        background: colors.slower,
        foreground: Colors.white,
        corner: l10n.brakeCorner(corner),
        title: l10n.brakeNow,
        large: true,
      ),
    };
  }
}

class _FullScreen extends StatelessWidget {
  const _FullScreen({
    required this.background,
    required this.foreground,
    required this.corner,
    required this.title,
    this.subtitle,
    this.large = false,
  });

  final Color background;
  final Color foreground;
  final String corner;
  final String title;
  final String? subtitle;
  final bool large;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: '$corner. $title',
    child: ColoredBox(
      color: background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  corner,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const Spacer(),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w900,
                    letterSpacing: large ? 8 : 2,
                    height: 1,
                    fontSize: constraints.maxHeight * (large ? 0.42 : 0.24),
                  ),
                ),
                if (subtitle case final text?)
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w800,
                      fontSize: constraints.maxHeight * 0.14,
                      fontFeatures: AppTheme.tabularFigures,
                    ),
                  ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
