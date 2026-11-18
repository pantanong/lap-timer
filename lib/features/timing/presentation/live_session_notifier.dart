import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lap_timer/app/infrastructure_providers.dart';
import 'package:lap_timer/core/result.dart';
import 'package:lap_timer/features/gps/data/gps_log_repository.dart';
import 'package:lap_timer/features/gps/domain/gps_fix.dart';
import 'package:lap_timer/features/gps/domain/gps_rate_meter.dart';
import 'package:lap_timer/features/gps/gps_providers.dart';
import 'package:lap_timer/features/race/domain/pit_lane_tracker.dart';
import 'package:lap_timer/features/race/domain/pit_stop.dart';
import 'package:lap_timer/features/race/domain/stint.dart';
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
  PitLaneTracker? _pitTracker;
  StintPlan _stints = StintPlan.start(const []);
  final GpsRateMeter _rateMeter = GpsRateMeter();

  /// Pit stops longer than this are closed automatically (missed exit
  /// line, e.g. GPS dropout).
  static const Duration _pitFallbackTimeout = Duration(minutes: 15);

  @override
  LiveSessionState build() {
    ref.onDispose(() {
      unawaited(_subscription?.cancel());
      unawaited(_logWriter?.close());
    });
    final config = ref.read(pendingSessionConfigProvider);
    _stints = StintPlan.start(config?.drivers ?? const []);
    return LiveSessionState(
      status: LiveSessionStatus.preparing,
      sectorCount: config?.sectorLayout?.sectorCount ?? 1,
      compareMode: config?.compareMode ?? SectorCompareMode.bestLap,
      raceRules: config?.raceRules,
      currentStint: _stints.current,
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
    final pitEntry = config.track.pitEntry;
    final pitExit = config.track.pitExit;
    if (config.raceRules != null && pitEntry != null && pitExit != null) {
      _pitTracker = PitLaneTracker(pitEntry: pitEntry, pitExit: pitExit);
    }
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
      raceRulesName: config.raceRules?.name,
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

  /// "Same driver" pressed while stopped in the pit: the current driver
  /// continues (with a new stint number) instead of the next one.
  void keepSameDriver() {
    final pit = state.pit;
    if (pit == null) return;
    state = state.copyWith(
      pit: pit.copyWith(
        sameDriver: true,
        nextStintLabel: _stints.nextStint(sameDriver: true).label,
      ),
    );
  }

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
    _onPitFix(fix, wallNow);
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

  /// Feeds the pit lane tracker and updates pit view, stints and stops.
  void _onPitFix(GpsFix fix, int wallNow) {
    final tracker = _pitTracker;
    final rules = state.raceRules;
    if (tracker == null || rules == null) return;
    for (final event in tracker.add(fix)) {
      switch (event) {
        case PitEntered(:final atMicros):
          state = state.copyWith(
            pit: PitView(
              entryMicros: atMicros,
              nextStintLabel: _stints.nextStint(sameDriver: false).label,
            ),
            clearPitResult: true,
          );
        case PitExited(:final stop):
          _completePitStop(stop, wallNow);
      }
    }
    final pit = state.pit;
    if (pit != null) {
      if (fix.timestampMicros - pit.entryMicros >
          _pitFallbackTimeout.inMicroseconds) {
        final stop = tracker.closeIfStillInPit(fix.timestampMicros);
        if (stop != null) _completePitStop(stop, wallNow);
        return;
      }
      final projected = tracker.projectedPitMicrosAtExit(
        fix.timestampMicros,
        fix.speedKmh,
      );
      state = state.copyWith(
        pit: pit.copyWith(
          maxSpeedKmh: tracker.maxSpeedKmh,
          projectedExitPitMicros: projected,
          clearProjection: projected == null,
          showNextDriver:
              tracker.hasStopped && fix.speedKmh < rules.resumeSpeedKmh,
        ),
      );
    }
    final result = state.pitResult;
    if (result != null && wallNow > result.untilWallMicros) {
      state = state.copyWith(clearPitResult: true);
    }
  }

  void _completePitStop(PitStop stop, int wallNow) {
    final rules = state.raceRules;
    final sameDriver = state.pit?.sameDriver ?? false;
    // A driver change only happens when the car actually stopped.
    if (stop.stopped) {
      _stints = _stints.advance(
        sameDriver: sameDriver,
        atMicros: stop.exitMicros,
      );
    }
    state = state.copyWith(
      clearPit: true,
      pitStops: [...state.pitStops, stop],
      currentStint: _stints.current,
      pitResult: PitResult(
        stop: stop,
        untilWallMicros:
            wallNow + (rules?.pitResultHold.inMicroseconds ?? 10000000),
      ),
    );
    unawaited(_saveSession());
  }

  LapFlash _flashFor(Lap lap, List<Lap> earlier, int wallNow) {
    final racing = [
      for (final l in earlier)
        if (!lapIncludesPitStop(l, state.pitStops)) l,
    ];
    final isPitLap =
        lapIncludesPitStop(lap, state.pitStops) || state.pit != null;
    final delta = LapReferences.lapDeltaMicros(lap, racing);
    return LapFlash(
      lap: lap,
      deltaMicros: delta,
      isBest: !isPitLap && (delta == null || delta < 0),
      untilWallMicros: wallNow + lapFlashDuration.inMicroseconds,
    );
  }

  Future<void> _saveSession() async {
    final session = _session;
    if (session == null) return;
    final updated = session.withProgress(
      laps: state.laps,
      stints: _stints.stints,
      pitStops: state.pitStops,
    );
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
