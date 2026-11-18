import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lap_timer/features/race/domain/race_rules.dart';
import 'package:lap_timer/features/timing/presentation/live_session_notifier.dart';
import 'package:lap_timer/features/timing/presentation/live_session_state.dart';
import 'package:lap_timer/features/timing/presentation/live_timing_widgets.dart';
import 'package:lap_timer/features/timing/presentation/time_format.dart';
import 'package:lap_timer/l10n/generated/app_localizations.dart';
import 'package:lap_timer/theme/app_colors.dart';
import 'package:lap_timer/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

/// Colour of the pit speed: green at or below the target, yellow up to the
/// limit, red above the limit.
Color pitSpeedColor(AppColors colors, RaceRules rules, double speedKmh) {
  if (speedKmh > rules.pitSpeedLimitKmh) return colors.slower;
  if (speedKmh > rules.pitTargetSpeedKmh) return colors.warning;
  return colors.faster;
}

/// The pit lane screen (mockups 5, 6 and 7): huge speed — or the next
/// driver's name while stopped — with the pit timer underneath; after the
/// exit line, the final pit time for a few seconds.
class PitLaneView extends StatelessWidget {
  /// Creates the view.
  const PitLaneView({required this.state, required this.onEnd, super.key});

  /// Session state (must have race rules).
  final LiveSessionState state;

  /// Ends the session (hold).
  final Future<void> Function() onEnd;

  @override
  Widget build(BuildContext context) {
    final rules = state.raceRules;
    if (rules == null) return const SizedBox.shrink();
    final pit = state.pit;
    final result = state.pitResult;
    if (pit == null && result != null) {
      return _PitResultView(result: result, rules: rules, state: state);
    }
    if (pit == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LiveStatusBar(state: state, onEnd: onEnd),
        Expanded(
          child: pit.showNextDriver
              ? _NextDriver(pit: pit)
              : _BigSpeed(rules: rules, speedKmh: state.speedKmh ?? 0),
        ),
        _PitTimerBar(state: state, pit: pit, rules: rules),
      ],
    );
  }
}

class _BigSpeed extends StatelessWidget {
  const _BigSpeed({required this.rules, required this.speedKmh});

  final RaceRules rules;
  final double speedKmh;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            speedKmh.toStringAsFixed(0),
            style: TextStyle(
              fontSize: constraints.maxHeight * 0.85,
              fontWeight: FontWeight.w800,
              height: 1,
              color: pitSpeedColor(colors, rules, speedKmh),
              fontFeatures: AppTheme.tabularFigures,
            ),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 16),
            child: Text(
              '${l10n.unitKmh}\n${l10n.pitLimit(rules.pitSpeedLimitKmh.round())}',
              style: TextStyle(color: colors.textMuted, fontSize: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class _NextDriver extends ConsumerWidget {
  const _NextDriver({required this.pit});

  final PitView pit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.pitNextDriver.toUpperCase(),
                style: TextStyle(color: colors.textMuted, letterSpacing: 1.2),
              ),
              Text(
                pit.nextStintLabel,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 84,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: SizedBox(
            height: 150,
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(color: colors.accent, width: 2),
                ),
              ),
              onPressed: pit.sameDriver
                  ? null
                  : () =>
                        ref.read(liveSessionProvider.notifier).keepSameDriver(),
              child: Text(
                pit.sameDriver ? l10n.pitSameDriverChosen : l10n.pitSameDriver,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PitTimerBar extends StatelessWidget {
  const _PitTimerBar({
    required this.state,
    required this.pit,
    required this.rules,
  });

  final LiveSessionState state;
  final PitView pit;
  final RaceRules rules;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    final target = rules.targetPitTime.inMicroseconds;
    final projected = pit.projectedExitPitMicros;
    return GpsNowBuilder(
      state: state,
      builder: (context, now) {
        final elapsed = now == null ? 0 : now - pit.entryMicros;
        final remaining = target - elapsed;
        final reached = remaining <= 0;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                _Value(
                  label: l10n.pitTime,
                  value: formatLapTime(elapsed, decimals: 1),
                  size: 40,
                ),
                const Spacer(),
                _Value(
                  label: l10n.pitToMinimum(formatLapTime(target, decimals: 0)),
                  value: reached
                      ? l10n.pitMinimumReached
                      : '−${formatLapTime(remaining, decimals: 1)}',
                  color: reached ? colors.faster : colors.warning,
                  size: 30,
                ),
                const Spacer(),
                if (projected != null && !reached)
                  _ProjectionChip(
                    ok: projected >= target,
                    projectedMicros: projected,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProjectionChip extends StatelessWidget {
  const _ProjectionChip({required this.ok, required this.projectedMicros});

  final bool ok;
  final int projectedMicros;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    final color = ok ? colors.faster : colors.warning;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          l10n.pitProjection(
            formatLapTime(projectedMicros, decimals: 1),
            ok ? l10n.pitOk : l10n.pitSlowDown,
          ),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

class _Value extends StatelessWidget {
  const _Value({
    required this.label,
    required this.value,
    required this.size,
    this.color,
  });

  final String label;
  final String value;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label.toUpperCase(),
        style: TextStyle(color: AppColors.of(context).textMuted, fontSize: 12),
      ),
      Text(
        value,
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w800,
          color: color,
          fontFeatures: AppTheme.tabularFigures,
        ),
      ),
    ],
  );
}

class _PitResultView extends StatelessWidget {
  const _PitResultView({
    required this.result,
    required this.rules,
    required this.state,
  });

  final PitResult result;
  final RaceRules rules;
  final LiveSessionState state;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    final stop = result.stop;
    final timeOk = stop.durationMicros >= rules.minimumPitTime.inMicroseconds;
    final speedOk = stop.maxSpeedKmh <= rules.pitSpeedLimitKmh;
    final color = timeOk && speedOk ? colors.faster : colors.slower;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.pitStopComplete(stop.number),
            style: TextStyle(
              color: color,
              letterSpacing: 3,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            formatLapTime(stop.durationMicros),
            style: TextStyle(
              fontSize: 120,
              fontWeight: FontWeight.w800,
              height: 1.1,
              color: color,
              fontFeatures: AppTheme.tabularFigures,
            ),
          ),
          Wrap(
            spacing: 12,
            children: [
              Chip(
                avatar: Icon(timeOk ? Icons.check : Icons.close, color: color),
                label: Text(
                  timeOk
                      ? l10n.pitMinimumOk(
                          formatLapTime(
                            rules.minimumPitTime.inMicroseconds,
                            decimals: 0,
                          ),
                        )
                      : l10n.pitMinimumMissed(
                          formatLapTime(
                            rules.minimumPitTime.inMicroseconds,
                            decimals: 0,
                          ),
                        ),
                ),
              ),
              Chip(
                avatar: Icon(
                  speedOk ? Icons.check : Icons.close,
                  color: speedOk ? colors.faster : colors.slower,
                ),
                label: Text(l10n.pitMaxSpeed(stop.maxSpeedKmh.round())),
              ),
              if (state.currentStint case final stint?)
                Chip(label: Text(l10n.pitNowDriving(stint.label))),
            ],
          ),
        ],
      ),
    );
  }
}
