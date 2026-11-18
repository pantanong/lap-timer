import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lap_timer/core/result.dart';
import 'package:lap_timer/features/gps/data/gps_log_repository.dart';
import 'package:lap_timer/features/gps/data/gps_source.dart';
import 'package:lap_timer/features/gps/domain/gps_fix.dart';
import 'package:lap_timer/features/gps/domain/gps_rate_meter.dart';
import 'package:lap_timer/features/gps/gps_providers.dart';

/// Lifecycle of the GPS monitor.
enum GpsMonitorStatus {
  /// Not receiving.
  idle,

  /// Asking for permission / opening the source.
  preparing,

  /// Receiving fixes.
  streaming,

  /// The source could not start; see [GpsMonitorState.failure].
  failed,
}

/// Immutable snapshot shown by the GPS monitor screen.
class GpsMonitorState {
  /// Creates a state; defaults describe "not started".
  const GpsMonitorState({
    this.status = GpsMonitorStatus.idle,
    this.latestFix,
    this.fixCount = 0,
    this.rateHz,
    this.isRecording = false,
    this.failure,
  });

  /// Current lifecycle step.
  final GpsMonitorStatus status;

  /// Most recent fix, if any.
  final GpsFix? latestFix;

  /// Fixes received since start.
  final int fixCount;

  /// Measured update rate, once enough fixes have arrived.
  final double? rateHz;

  /// Whether fixes are being written to a raw log.
  final bool isRecording;

  /// Why the source failed, when [status] is failed.
  final GpsFailure? failure;

  /// Returns a copy with the given fields replaced.
  GpsMonitorState copyWith({
    GpsMonitorStatus? status,
    GpsFix? latestFix,
    int? fixCount,
    double? rateHz,
    bool? isRecording,
    GpsFailure? failure,
  }) => GpsMonitorState(
    status: status ?? this.status,
    latestFix: latestFix ?? this.latestFix,
    fixCount: fixCount ?? this.fixCount,
    rateHz: rateHz ?? this.rateHz,
    isRecording: isRecording ?? this.isRecording,
    failure: failure ?? this.failure,
  );
}

/// ViewModel of the GPS monitor: starts/stops the selected source, measures
/// its rate and optionally records the raw fixes.
class GpsMonitorNotifier extends Notifier<GpsMonitorState> {
  StreamSubscription<GpsFix>? _subscription;
  GpsLogWriter? _writer;
  final GpsRateMeter _rateMeter = GpsRateMeter();

  @override
  GpsMonitorState build() {
    ref.onDispose(() {
      unawaited(_subscription?.cancel());
      unawaited(_writer?.close());
    });
    return const GpsMonitorState();
  }

  /// Prepares the selected source and starts listening.
  Future<void> start() async {
    final source = ref.read(gpsSourceProvider);
    if (source == null || state.status == GpsMonitorStatus.streaming) return;
    state = const GpsMonitorState(status: GpsMonitorStatus.preparing);
    final prepared = await source.prepare();
    if (!ref.mounted) return;
    switch (prepared) {
      case Err(:final failure):
        state = GpsMonitorState(
          status: GpsMonitorStatus.failed,
          failure: failure,
        );
      case Ok():
        _rateMeter.reset();
        _subscription = source.fixes().listen(
          _onFix,
          onDone: () => unawaited(stop()),
        );
        state = state.copyWith(status: GpsMonitorStatus.streaming);
    }
  }

  /// Stops listening and closes any open recording.
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _stopRecording();
    if (!ref.mounted) return;
    state = state.copyWith(status: GpsMonitorStatus.idle);
  }

  /// Starts or stops writing raw fixes to a new log file.
  Future<void> toggleRecording() async {
    if (_writer != null) {
      await _stopRecording();
      return;
    }
    _writer = await ref.read(gpsLogRepositoryProvider).startRecording();
    if (!ref.mounted) return;
    state = state.copyWith(isRecording: true);
  }

  Future<void> _stopRecording() async {
    final writer = _writer;
    if (writer == null) return;
    _writer = null;
    await writer.close();
    if (!ref.mounted) return;
    ref.invalidate(gpsLogsProvider);
    state = state.copyWith(isRecording: false);
  }

  void _onFix(GpsFix fix) {
    final writer = _writer;
    writer?.add(fix);
    state = state.copyWith(
      latestFix: fix,
      fixCount: state.fixCount + 1,
      rateHz: _rateMeter.add(fix.timestampMicros),
    );
  }
}

/// The GPS monitor ViewModel.
final NotifierProvider<GpsMonitorNotifier, GpsMonitorState> gpsMonitorProvider =
    NotifierProvider.autoDispose<GpsMonitorNotifier, GpsMonitorState>(
      GpsMonitorNotifier.new,
    );
