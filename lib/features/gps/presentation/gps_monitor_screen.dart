import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lap_timer/core/screen_awake_service.dart';
import 'package:lap_timer/features/gps/presentation/gps_failure_message.dart';
import 'package:lap_timer/features/gps/presentation/gps_monitor_notifier.dart';
import 'package:lap_timer/l10n/generated/app_localizations.dart';
import 'package:lap_timer/theme/app_colors.dart';
import 'package:lap_timer/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

/// Diagnostics screen: shows live speed, update rate and accuracy of the
/// selected GPS source, and can record a raw log. Used to check a GPS setup
/// before going on track.
class GpsMonitorScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const GpsMonitorScreen({super.key});

  @override
  ConsumerState<GpsMonitorScreen> createState() => _GpsMonitorScreenState();
}

class _GpsMonitorScreenState extends ConsumerState<GpsMonitorScreen> {
  late final ScreenAwakeService _screenAwake;

  @override
  void initState() {
    super.initState();
    // Keep the screen on while this screen is visible.
    _screenAwake = ref.read(screenAwakeServiceProvider);
    unawaited(_screenAwake.keepOn());
  }

  @override
  void dispose() {
    unawaited(_screenAwake.release());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(gpsMonitorProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.monitorTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _SpeedReadout(state: state)),
              _StatsRow(state: state),
              const SizedBox(height: 16),
              _MonitorControls(state: state),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeedReadout extends StatelessWidget {
  const _SpeedReadout({required this.state});

  final GpsMonitorState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final failure = state.failure;
    if (state.status == GpsMonitorStatus.failed && failure != null) {
      return Center(
        child: Text(
          gpsFailureMessage(l10n, failure),
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.slower, fontSize: 18),
        ),
      );
    }
    final fix = state.latestFix;
    if (fix == null) {
      final text = state.status == GpsMonitorStatus.idle
          ? ''
          : l10n.monitorWaiting;
      return Center(child: Text(text));
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          fix.speedKmh.toStringAsFixed(0),
          style: const TextStyle(
            fontSize: 140,
            fontWeight: FontWeight.w800,
            height: 1,
            fontFeatures: AppTheme.tabularFigures,
          ),
        ),
        Text(
          l10n.unitKmh,
          style: TextStyle(color: colors.textMuted, fontSize: 22),
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.state});

  final GpsMonitorState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rate = state.rateHz;
    final accuracy = state.latestFix?.horizontalAccuracyMetres;
    return Row(
      children: [
        _Stat(
          label: l10n.monitorRate,
          value: rate == null ? '—' : l10n.unitHz(rate.toStringAsFixed(1)),
        ),
        _Stat(
          label: l10n.monitorAccuracy,
          value: accuracy == null
              ? '—'
              : l10n.unitMetres(accuracy.toStringAsFixed(1)),
        ),
        _Stat(label: l10n.monitorFixes, value: '${state.fixCount}'),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              fontFeatures: AppTheme.tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonitorControls extends ConsumerWidget {
  const _MonitorControls({required this.state});

  final GpsMonitorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(gpsMonitorProvider.notifier);
    final streaming = state.status == GpsMonitorStatus.streaming;
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            onPressed: () =>
                unawaited(streaming ? notifier.stop() : notifier.start()),
            child: Text(streaming ? l10n.monitorStop : l10n.monitorStart),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton(
            onPressed: streaming
                ? () => unawaited(notifier.toggleRecording())
                : null,
            child: Text(
              state.isRecording
                  ? l10n.monitorStopRecording
                  : l10n.monitorRecord,
            ),
          ),
        ),
      ],
    );
  }
}
