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
          return Row(
            children: [
              Expanded(
                flex: 3,
                child: _MainNumber(content: content, fontSize: big),
              ),
              Expanded(
                flex: 2,
                child: _HeadlineSide(
                  state: state,
                  finishedLap: finishedLapShown(content, state),
                  // About 25 % larger than before, for reading at speed.
                  fontSize: big * 0.45,
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

/// The big number: a time, followed for a few seconds by a gap in
/// brackets, e.g. `1:44.4 (−2.75)`. The time keeps its colour (white, or
/// purple for a new best lap); the bracketed gap is green when faster and
/// red when slower. The text is scaled down when needed so it always fits.
class _MainNumber extends StatelessWidget {
  const _MainNumber({required this.content, required this.fontSize});

  final HeadlineContent content;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final (
      int? timeMicros,
      int decimals,
      Color timeColor,
      int? gap,
    ) = switch (content) {
      RunningLapHeadline(:final elapsedMicros) => (
        elapsedMicros,
        1,
        colors.textPrimary,
        null,
      ),
      SectorGapHeadline(:final sector, :final timeMicros, :final finishedLap) =>
        (
          timeMicros,
          // A finished lap shows hundredths, a running one tenths.
          finishedLap == null ? 1 : 2,
          finishedLap?.isBest ?? false
              ? colors.personalBest
              : colors.textPrimary,
          sector.deltaMicros,
        ),
      LapGapHeadline(:final flash) => (
        flash.lap.timeMicros,
        2,
        flash.isBest ? colors.personalBest : colors.textPrimary,
        flash.deltaMicros,
      ),
    };
    final timeText = timeMicros == null
        ? '--:--.-'
        : formatLapTime(timeMicros, decimals: decimals);
    final gapText = gap == null ? null : ' (${formatDelta(gap)})';
    const style = TextStyle(
      fontWeight: FontWeight.w800,
      height: 1,
      fontFeatures: AppTheme.tabularFigures,
    );
    final span = TextSpan(
      children: [
        TextSpan(
          text: timeText,
          style: style.copyWith(color: timeColor),
        ),
        if (gapText != null && gap != null)
          TextSpan(
            text: gapText,
            style: style.copyWith(color: deltaColor(colors, gap)),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Measure at size 100 with the same font the Text will use, then
        // scale to fit both height and width.
        final base = DefaultTextStyle.of(context).style.merge(style);
        final painter = TextPainter(
          text: TextSpan(style: base.copyWith(fontSize: 100), children: [span]),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final widthAt100 = painter.width;
        painter.dispose();
        final fitted = widthAt100 <= 0
            ? fontSize
            // 3 % margin so rounding never pushes the gap off the line.
            : math.min(
                fontSize,
                constraints.maxWidth / widthAt100 * 100 * 0.97,
              );
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text.rich(
            TextSpan(
              style: style.copyWith(fontSize: fitted),
              children: [span],
            ),
            maxLines: 1,
            softWrap: false,
          ),
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
      value = formatLapTime(lap.timeMicros);
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
    final label = data.kind == SectorBoxKind.done && time != null
        ? 'S${data.index + 1} · ${formatLapTime(time)}'
        : 'S${data.index + 1}${data.kind == SectorBoxKind.running ? ' ›' : ''}';
    return LayoutBuilder(
      builder: (context, constraints) => DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border, width: 2.5),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(color: colors.textMuted, fontSize: 13),
              ),
              const Spacer(),
              Text(
                big,
                maxLines: 1,
                style: TextStyle(
                  // Fit both the box height and its width (≈0.62 em per
                  // glyph for tabular digits).
                  fontSize: math.min(
                    constraints.maxHeight * (compact ? 0.32 : 0.48),
                    (constraints.maxWidth - 24) / (big.length * 0.62),
                  ),
                  fontWeight: FontWeight.w800,
                  height: 1,
                  color: bigColor,
                  fontFeatures: AppTheme.tabularFigures,
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
        style: TextStyle(color: AppColors.of(context).textMuted, fontSize: 11),
      ),
      Text(
        value,
        style: TextStyle(
          // About 30 % larger than before, for reading at speed.
          fontSize: 32,
          fontWeight: FontWeight.w700,
          height: 1.1,
          color: color,
          fontFeatures: AppTheme.tabularFigures,
        ),
      ),
    ],
  );
}
