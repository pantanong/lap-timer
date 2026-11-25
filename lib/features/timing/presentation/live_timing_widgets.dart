import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lap_timer/app/infrastructure_providers.dart';
import 'package:lap_timer/features/brake_coach/domain/brake_coach.dart';
import 'package:lap_timer/features/timing/domain/lap.dart';
import 'package:lap_timer/features/timing/domain/lap_comparison.dart';
import 'package:lap_timer/features/timing/presentation/headline_content.dart';
import 'package:lap_timer/features/timing/presentation/live_session_notifier.dart';
import 'package:lap_timer/features/timing/presentation/live_session_state.dart';
import 'package:lap_timer/features/timing/presentation/sector_box_data.dart';
import 'package:lap_timer/features/timing/presentation/time_format.dart';
import 'package:lap_timer/l10n/generated/app_localizations.dart';
import 'package:lap_timer/theme/app_colors.dart';
import 'package:lap_timer/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

/// Rebuilds its child ~20 times a second with the estimated GPS "now", so
/// running times tick smoothly between GPS fixes.
class GpsNowBuilder extends ConsumerStatefulWidget {
  /// Creates the builder.
  const GpsNowBuilder({required this.state, required this.builder, super.key});

  /// Session state used to convert wall time to GPS time.
  final LiveSessionState state;

  /// Builds the child for a GPS time (null before the first fix).
  final Widget Function(BuildContext context, int? gpsNowMicros) builder;

  @override
  ConsumerState<GpsNowBuilder> createState() => _GpsNowBuilderState();
}

class _GpsNowBuilderState extends ConsumerState<GpsNowBuilder> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wallNow = ref.read(clockProvider).now().microsecondsSinceEpoch;
    return widget.builder(context, widget.state.gpsNowMicros(wallNow));
  }
}

/// Colour for a delta: faster green, slower red, none muted.
Color deltaColor(AppColors colors, int? deltaMicros) {
  if (deltaMicros == null) return colors.textMuted;
  return deltaMicros <= 0 ? colors.faster : colors.slower;
}

/// Top row: GPS status, lap number, End button (hold to end).
class LiveStatusBar extends StatelessWidget {
  /// Creates the bar.
  const LiveStatusBar({required this.state, required this.onEnd, super.key});

  /// Session state.
  final LiveSessionState state;

  /// Called when the user holds the End button.
  final Future<void> Function() onEnd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final rate = state.gpsRateHz;
    final gpsOk = rate != null;
    return Row(
      children: [
        Icon(
          Icons.satellite_alt,
          size: 18,
          color: gpsOk ? colors.faster : colors.warning,
        ),
        const SizedBox(width: 6),
        Text(
          gpsOk ? l10n.unitHz(rate.toStringAsFixed(0)) : l10n.liveWaitingGps,
          style: TextStyle(color: colors.textMuted),
        ),
        const Spacer(),
        Text(
          [
            ?state.currentStint?.label,
            if (state.currentLapStartMicros == null)
              l10n.liveWaitingStartLine
            else
              l10n.liveLapNumber(state.lapNumber),
          ].join(' · '),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const Spacer(),
        if (state.brakeCoachPhase == BrakeCoachPhase.learning)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: Text(
              l10n.brakeLearning(
                state.brakeLearningLaps,
                state.brakeLearningLapsNeeded,
              ),
              style: TextStyle(color: colors.warning, fontSize: 13),
            ),
          ),
        if (state.raceRules case final rules?)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: Text(
              l10n.livePitCount(state.pitStops.length, rules.requiredPitStops),
              style: TextStyle(
                color: state.pitStops.length >= rules.requiredPitStops
                    ? colors.faster
                    : colors.textMuted,
                fontSize: 13,
              ),
            ),
          ),
        Tooltip(
          message: l10n.liveHoldToEnd,
          child: OutlinedButton(
            onPressed: () =>
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(l10n.liveHoldToEnd))),
            onLongPress: () => unawaited(onEnd()),
            child: Text(l10n.liveEnd),
          ),
        ),
      ],
    );
  }
}

/// Top of the live screen: the big number (running lap time, or the gap
/// of a sector / lap just completed) and, on the right, the predicted lap
/// (or the time of the lap just completed).
class LiveHeadline extends ConsumerWidget {
  /// Creates the headline.
  const LiveHeadline({required this.state, super.key});

  /// Session state.
  final LiveSessionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) => LayoutBuilder(
    builder: (context, constraints) {
      final big = constraints.maxHeight * 0.82;
      return GpsNowBuilder(
        state: state,
        builder: (context, gpsNow) {
          final wallNow = ref.read(clockProvider).now().microsecondsSinceEpoch;
          final content = headlineContentAt(
            state,
            wallNowMicros: wallNow,
            gpsNowMicros: gpsNow,
          );
          // The side panel takes only the width it needs; the big number
          // gets all the rest (no empty gap between them).
          return Row(
            children: [
              Expanded(
                child: _MainNumber(
                  content: content,
                  liveDeltaMicros: state.liveDeltaMicros,
                  fontSize: big,
                ),
              ),
              const SizedBox(width: 16),
              _HeadlineSide(
                state: state,
                finishedLap: finishedLapShown(content, state),
                // About 25 % larger than before, for reading at speed.
                fontSize: big * 0.45,
              ),
            ],
          );
        },
      );
    },
  );
}

/// The top row: two fixed columns, `[ time ] [ (gap) ]`.
///
/// - Time: the running lap time, or the finished lap's time at lap end
///   (purple for a new best lap).
/// - Gap, always in the same place: the gap of a sector / lap just
///   completed for a few seconds, otherwise the live gap to the best lap.
///   Green when faster, red when slower; empty without a best lap.
///
/// The font size is computed from the widest possible values ("8:88.8" and
/// "(−88.88)"), so neither column ever moves or resizes as numbers change.
class _MainNumber extends StatelessWidget {
  const _MainNumber({
    required this.content,
    required this.liveDeltaMicros,
    required this.fontSize,
  });

  final HeadlineContent content;
  final int? liveDeltaMicros;
  final double fontSize;

  static const String _widestTime = '8:88.8';
  static const String _widestGap = ' (\u221288.88)';

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final (int? timeMicros, Color timeColor, int? gap) = switch (content) {
      RunningLapHeadline(:final elapsedMicros) => (
        elapsedMicros,
        colors.textPrimary,
        liveDeltaMicros,
      ),
      SectorGapHeadline(:final sector, :final timeMicros, :final finishedLap) =>
        (
          timeMicros,
          finishedLap?.isBest ?? false
              ? colors.personalBest
              : colors.textPrimary,
          sector.deltaMicros,
        ),
      LapGapHeadline(:final flash) => (
        flash.lap.timeMicros,
        flash.isBest ? colors.personalBest : colors.textPrimary,
        flash.deltaMicros,
      ),
    };
    // Tenths on the top row (hundredths are in Last/Best and the gap).
    final timeText = timeMicros == null
        ? '--:--.-'
        : formatLapTime(timeMicros, decimals: 1);
    final gapText = gap == null ? '' : ' (${formatDelta(gap)})';
    const style = TextStyle(
      fontWeight: FontWeight.w800,
      height: 1,
      fontFeatures: AppTheme.tabularFigures,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final base = DefaultTextStyle.of(context).style.merge(style);
        final scaler = MediaQuery.textScalerOf(context);
        final direction = Directionality.of(context);
        double widthAt100(String text) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: base.copyWith(fontSize: 100)),
            textDirection: direction,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final w = painter.width;
          painter.dispose();
          return w;
        }

        final timeW = widthAt100(_widestTime);
        final gapW = widthAt100(_widestGap);
        // 3 % margin so rounding never pushes text off its column.
        final size = math.min(
          fontSize,
          constraints.maxWidth / (timeW + gapW) * 100 * 0.97,
        );
        final timeColumn = timeW * size / 100;
        return Row(
          children: [
            SizedBox(
              width: timeColumn,
              child: Text(
                timeText,
                maxLines: 1,
                softWrap: false,
                style: style.copyWith(fontSize: size, color: timeColor),
              ),
            ),
            Expanded(
              child: Text(
                gapText,
                maxLines: 1,
                softWrap: false,
                style: style.copyWith(
                  fontSize: size,
                  color: gap == null ? null : deltaColor(colors, gap),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HeadlineSide extends StatelessWidget {
  const _HeadlineSide({
    required this.state,
    required this.finishedLap,
    required this.fontSize,
  });

  final LiveSessionState state;
  final Lap? finishedLap;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final flash = state.flash;
    final lap = finishedLap;
    final String label;
    final String? value;
    final Color valueColor;
    int? delta;
    if (lap != null && flash != null) {
      // End of lap: the big number shows the gap; keep the lap time here.
      label = flash.isBest ? l10n.liveNewBestLap : l10n.liveLapComplete;
      value = formatLapTime(lap.timeMicros, decimals: 1);
      valueColor = flash.isBest ? colors.personalBest : colors.textPrimary;
    } else {
      label = l10n.livePredictedLap;
      final refs = state.references;
      final predicted = refs.predictedLapMicros(
        state.currentLapSectors,
        state.compareMode,
      );
      final best = refs.bestLap?.timeMicros;
      value = predicted == null ? null : formatLapTime(predicted, decimals: 1);
      delta = predicted == null || best == null ? null : predicted - best;
      valueColor = deltaColor(colors, delta);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label.toUpperCase(),
          maxLines: 1,
          style: TextStyle(color: colors.textMuted, letterSpacing: 1.2),
        ),
        if (value != null)
          Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: fontSize * 0.75,
              fontWeight: FontWeight.w800,
              height: 1.15,
              color: valueColor,
              fontFeatures: AppTheme.tabularFigures,
            ),
          ),
        if (delta != null)
          Text(
            formatDelta(delta),
            maxLines: 1,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              height: 1.1,
              color: deltaColor(colors, delta),
              fontFeatures: AppTheme.tabularFigures,
            ),
          ),
      ],
    );
  }
}

/// One box per sector; compact when there are more than six.
class SectorBoxesRow extends StatelessWidget {
  /// Creates the row.
  const SectorBoxesRow({required this.state, super.key});

  /// Session state.
  final LiveSessionState state;

  @override
  Widget build(BuildContext context) => GpsNowBuilder(
    state: state,
    builder: (context, now) {
      final boxes = buildSectorBoxes(state, now);
      return Row(
        children: [
          for (final box in boxes)
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 4),
                child: SectorBox(data: box, compact: boxes.length > 6),
              ),
            ),
        ],
      );
    },
  );
}

/// A single sector box (see mockup 11).
class SectorBox extends StatelessWidget {
  /// Creates the box.
  const SectorBox({required this.data, required this.compact, super.key});

  /// What to show.
  final SectorBoxData data;

  /// Smaller text when many sectors share the row.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final time = data.timeMicros;
    final delta = data.deltaMicros;
    final (Color border, String big, Color bigColor) = switch (data.kind) {
      SectorBoxKind.done when delta != null => (
        deltaColor(colors, delta),
        formatDelta(delta),
        deltaColor(colors, delta),
      ),
      SectorBoxKind.done => (
        colors.outline,
        time == null ? '—' : formatLapTime(time),
        colors.textPrimary,
      ),
      SectorBoxKind.running => (
        colors.accent,
        time == null ? '—' : formatLapTime(time, decimals: 1),
        colors.textPrimary,
      ),
      SectorBoxKind.pending => (colors.outline, '—', colors.textMuted),
    };
    final name =
        'S${data.index + 1}${data.kind == SectorBoxKind.running ? ' ›' : ''}';
    // The sector's own time is shown in yellow next to its name.
    final sectorTime = data.kind == SectorBoxKind.done && time != null
        ? formatLapTime(time)
        : null;
    return LayoutBuilder(
      builder: (context, constraints) => DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border, width: 2.5),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text.rich(
                TextSpan(
                  text: name,
                  children: [
                    if (sectorTime != null)
                      TextSpan(
                        text: ' · $sectorTime',
                        style: TextStyle(
                          color: colors.warning,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(color: colors.textMuted, fontSize: 13),
              ),
              // The number always stays inside the box: sized from the box,
              // and scaled down further if it would still not fit.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    big,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: math.min(
                        // Box height minus the label line.
                        (constraints.maxHeight - 26) * (compact ? 0.7 : 0.92),
                        (constraints.maxWidth - 24) / (big.length * 0.62),
                      ),
                      fontWeight: FontWeight.w800,
                      height: 1,
                      color: bigColor,
                      fontFeatures: AppTheme.tabularFigures,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom row: last lap, best lap, and the compare-mode toggle.
class LiveFooter extends ConsumerWidget {
  /// Creates the footer.
  const LiveFooter({required this.state, super.key});

  /// Session state.
  final LiveSessionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final last = state.laps.isEmpty ? null : state.laps.last.timeMicros;
    final best = state.references.bestLap?.timeMicros;
    final mode = state.compareMode;
    return Row(
      children: [
        _FooterValue(
          label: l10n.liveLast,
          value: last == null ? '—' : formatLapTime(last),
        ),
        const SizedBox(width: 28),
        _FooterValue(
          label: l10n.liveBest,
          value: best == null ? '—' : formatLapTime(best),
          color: colors.personalBest,
        ),
        const Spacer(),
        TextButton(
          onPressed: () => ref.read(liveSessionProvider.notifier).compareMode =
              mode == SectorCompareMode.bestLap
              ? SectorCompareMode.bestSector
              : SectorCompareMode.bestLap,
          child: Text(
            mode == SectorCompareMode.bestLap
                ? l10n.compareBestLap
                : l10n.compareBestSector,
          ),
        ),
      ],
    );
  }
}

class _FooterValue extends StatelessWidget {
  const _FooterValue({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label.toUpperCase(),
        style: TextStyle(color: AppColors.of(context).textMuted, fontSize: 13),
      ),
      Text(
        value,
        style: TextStyle(
          // Twice the first version, for reading at speed.
          fontSize: 48,
          fontWeight: FontWeight.w700,
          height: 1.1,
          color: color,
          fontFeatures: AppTheme.tabularFigures,
        ),
      ),
    ],
  );
}
