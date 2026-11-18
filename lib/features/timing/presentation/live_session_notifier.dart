import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lap_timer/app/infrastructure_providers.dart';
import 'package:lap_timer/core/result.dart';
import 'package:lap_timer/features/gps/data/gps_log_repository.dart';
import 'package:lap_timer/features/gps/domain/gps_fix.dart';
import 'package:lap_timer/features/gps/domain/gps_rate_meter.dart';
import 'package:lap_timer/features/gps/gps_providers.dart';
import 'package:lap_timer/features/sessions/domain/session.dart';
import 'package:lap_timer/features/timing/domain/lap.dart';
import 'package:lap_timer/features/timing/domain/lap_comparison.dart';
import 'package:lap_timer/features/timing/domain/lap_timing_engine.dart';
import 'package:lap_timer/features/timing/presentation/live_session_state.dart';

/// The configuration for the next live session, set by the New Session
/// screen just before opening the live screen.
final NotifierProvider<PendingSessionConfigNotifier, LiveSessionConfig?>
pendingSessionConfigProvider =
    NotifierProvider<PendingSessionConfigNotifier, LiveSessionConfig?>(
      PendingSessionConfigNotifier.new,
    );

/// Holds the configuration chosen on the New Session screen.
class PendingSessionConfigNotifier extends Notifier<LiveSessionConfig?> {
  @override
  LiveSessionConfig? build() => null;

  /// The configuration to use.
  LiveSessionConfig? get config => state;

  /// Sets the configuration to use.
  set config(LiveSessionConfig? value) => state = value;
}

/// How long the lap-complete banner stays on screen.
const Duration lapFlashDuration = Duration(seconds: 5);

/// ViewModel of the live timing screen.
///
/// Wires the selected GPS source to the [LapTimingEngine], records the raw
/// GPS log, saves the session after every lap (nothing is lost if the app
/// is killed) and exposes an immutable [LiveSessionState].
class LiveSessionNotifier extends Notifier<LiveSessionState> {
  StreamSubscription<GpsFix>? _subscription;
  GpsLogWriter? _logWriter;
  LapTimingEngine? _engine;
  Session? _session;
  final GpsRateMeter _rateMeter = GpsRateMeter();

  @override
  LiveSessionState build() {
    ref.onDispose(() {
      unawaited(_subscription?.cancel());
      unawaited(_logWriter?.close());
    });
    final config = ref.read(pendingSessionConfigProvider);
    return LiveSessionState(
      status: LiveSessionStatus.preparing,
      sectorCount: config?.sectorLayout?.sectorCount ?? 1,
      compareMode: config?.compareMode ?? SectorCompareMode.bestLap,
    );
  }

  /// Opens the GPS source and starts timing with the pending config.
  Future<void> start() async {
    final config = ref.read(pendingSessionConfigProvider);
    final source = ref.read(gpsSourceProvider);
    final startFinish = config?.track.startFinish;
    if (config == null || source == null || startFinish == null) return;
    if (_subscription != null) return;

    final prepared = await source.prepare();
    if (!ref.mounted) return;
    if (prepared case Err(:final failure)) {
      state = state.copyWith(
        status: LiveSessionStatus.failed,
        failure: failure,
      );
      return;
    }

    _engine = LapTimingEngine(
      startFinish: startFinish,
      splits: config.sectorLayout?.splits ?? const [],
    );
    _logWriter = await ref.read(gpsLogRepositoryProvider).startRecording();
    if (!ref.mounted) return;
    final now = ref.read(clockProvider).now();
    _session = Session(
      id: now.toIso8601String().replaceAll(RegExp('[:.]'), '-'),
      trackId: config.track.id,
      trackName: config.track.name,
      sectorLayoutName: config.sectorLayout?.name ?? '—',
      sectorCount: config.sectorLayout?.sectorCount ?? 1,
      vehicleType: config.vehicleType,
      startedAt: now,
      laps: const [],
      gpsLogFileName: _logWriter?.info.fileName,
    );
    _subscription = source.fixes().listen(
      _onFix,
      onDone: () => unawaited(end()),
    );
    state = state.copyWith(status: LiveSessionStatus.running);
  }

  /// Switches what sector deltas compare against.
  set compareMode(SectorCompareMode mode) =>
      state = state.copyWith(compareMode: mode);

  /// The active comparison mode.
  SectorCompareMode get compareMode => state.compareMode;

  /// Stops timing, saves the session and closes the GPS log.
  Future<void> end() async {
    await _subscription?.cancel();
    _subscription = null;
    await _logWriter?.close();
    _logWriter = null;
    await _saveSession();
    ref.invalidate(gpsLogsProvider);
    if (!ref.mounted) return;
    state = state.copyWith(status: LiveSessionStatus.ended);
  }

  void _onFix(GpsFix fix) {
    final writer = _logWriter;
    writer?.add(fix);
    final engine = _engine;
    if (engine == null) return;
    final wallNow = ref.read(clockProvider).now().microsecondsSinceEpoch;
    final events = engine.add(fix);

    var laps = state.laps;
    var flash = state.flash;
    for (final event in events) {
      if (event is LapCompleted) {
        flash = _flashFor(event.lap, laps, wallNow);
        laps = [...laps, event.lap];
      }
    }
    final flashExpired = flash != null && wallNow > flash.untilWallMicros;
    state = state.copyWith(
      laps: laps,
      lapNumber: engine.currentLapNumber,
      currentLapStartMicros: engine.currentLapStartMicros,
      currentSectorIndex: engine.currentSectorIndex,
      currentLapSectors: engine.currentLapSectors,
      currentSectorStartMicros: engine.currentSectorStartMicros,
      lastFixMicros: fix.timestampMicros,
      lastFixWallMicros: wallNow,
      speedKmh: fix.speedKmh,
      gpsRateHz: _rateMeter.add(fix.timestampMicros),
      flash: flash,
      clearFlash: flash == null || flashExpired,
    );
    if (events.any((e) => e is LapCompleted)) unawaited(_saveSession());
  }

  LapFlash _flashFor(Lap lap, List<Lap> earlier, int wallNow) {
    final delta = LapReferences.lapDeltaMicros(lap, earlier);
    return LapFlash(
      lap: lap,
      deltaMicros: delta,
      isBest: delta == null || delta < 0,
      untilWallMicros: wallNow + lapFlashDuration.inMicroseconds,
    );
  }

  Future<void> _saveSession() async {
    final session = _session;
    if (session == null) return;
    final updated = session.withLaps(state.laps);
    _session = updated;
    await ref.read(sessionRepositoryProvider).save(updated);
  }
}

/// The live session ViewModel; lives as long as the live screen.
final NotifierProvider<LiveSessionNotifier, LiveSessionState>
liveSessionProvider =
    NotifierProvider.autoDispose<LiveSessionNotifier, LiveSessionState>(
      LiveSessionNotifier.new,
    );
