import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lap_timer/app/infrastructure_providers.dart';
import 'package:lap_timer/core/geo/local_point.dart';
import 'package:lap_timer/core/result.dart';
import 'package:lap_timer/features/brake_coach/domain/brake_alert.dart';
import 'package:lap_timer/features/brake_coach/domain/brake_coach.dart';
import 'package:lap_timer/features/brake_coach/domain/brake_profile.dart';
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
import 'package:lap_timer/features/timing/domain/live_delta.dart';
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
  BrakeCoach? _brakeCoach;
  LiveDeltaTracker? _liveDelta;
  StintPlan _stints = StintPlan.start(const []);

  /// Driver names were entered: show them (otherwise "Driver(1)" would
  /// only be noise during practice).
  bool _hasDrivers = false;
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
    _hasDrivers = config?.drivers.isNotEmpty ?? false;
    return LiveSessionState(
      status: LiveSessionStatus.preparing,
      sectorCount: config?.sectorLayout?.sectorCount ?? 1,
      compareMode: config?.compareMode ?? SectorCompareMode.bestLap,
      raceRules: config?.raceRules,
      currentStint: _hasDrivers ? _stints.current : null,
      brakeCoachPhase: _brakeCoachEnabled(config)
          ? (config?.brakeProfile == null
                ? BrakeCoachPhase.learning
                : BrakeCoachPhase.active)
          : null,
      brakeLearningLapsNeeded: config?.brakeCoach?.learningLaps ?? 0,
    );
  }

  /// The brake coach never runs for bicycles.
  static bool _brakeCoachEnabled(LiveSessionConfig? config) =>
      config != null &&
      config.brakeCoach != null &&
      config.vehicleType != VehicleType.bicycle;

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

    final coachSettings = config.brakeCoach;
    if (coachSettings != null && _brakeCoachEnabled(config)) {
      _brakeCoach = BrakeCoach(
        settings: coachSettings,
        projection: LocalProjection(
          originLatitude: startFinish.latitude,
          originLongitude: startFinish.longitude,
        ),
        startingProfile: config.brakeProfile,
      );
    }
    _liveDelta = LiveDeltaTracker(
      LocalProjection(
        originLatitude: startFinish.latitude,
        originLongitude: startFinish.longitude,
      ),
    );
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
    var sectorFlash = state.sectorFlash;
    final display =
        ref.read(pendingSessionConfigProvider)?.deltaDisplay ??
        const DeltaDisplaySettings();
    for (final event in events) {
      if (event is SectorCompleted) {
        sectorFlash = SectorFlash(
          sectorIndex: event.sectorIndex,
          sectorMicros: event.sectorMicros,
          deltaMicros: state.references.sectorDeltaMicros(
            event.sectorIndex,
            event.sectorMicros,
            state.compareMode,
          ),
          untilWallMicros: wallNow + display.sectorHold.inMicroseconds,
        );
      }
      if (event is LapCompleted) {
        sectorFlash = null;
        flash = _flashFor(event.lap, laps, wallNow, display);
        laps = [...laps, event.lap];
        final isRacingLap =
            state.pit == null && !lapIncludesPitStop(event.lap, state.pitStops);
        _brakeCoach?.completeLap(
          lapNumber: event.lap.number,
          lapTimeMicros: event.lap.timeMicros,
          isRacingLap: isRacingLap,
        );
        _liveDelta?.completeLap(
          lapMicros: event.lap.timeMicros,
          isRacingLap: isRacingLap,
        );
      }
      if (event is LapStarted) {
        _brakeCoach?.startLap();
        _liveDelta?.startLap(event.atMicros);
      }
    }
    final flashExpired = flash != null && wallNow > flash.untilWallMicros;
    final sectorFlashExpired =
        sectorFlash != null && wallNow > sectorFlash.untilWallMicros;
    _onPitFix(fix, wallNow);
    _onBrakeCoachFix(fix);
    final liveDelta = _liveDelta?.add(
      latitude: fix.latitude,
      longitude: fix.longitude,
      timeMicros: fix.timestampMicros,
    );
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
      sectorFlash: sectorFlash,
      clearSectorFlash: sectorFlash == null || sectorFlashExpired,
      // No live delta in the pit lane.
      liveDeltaMicros: liveDelta,
      clearLiveDelta: liveDelta == null || state.pit != null,
    );
    if (events.any((e) => e is LapCompleted)) unawaited(_saveSession());
  }

  /// Feeds the brake coach; no alerts in the pit lane.
  void _onBrakeCoachFix(GpsFix fix) {
    final coach = _brakeCoach;
    if (coach == null) return;
    final alert = coach.addFix(fix);
    state = state.copyWith(
      brakeAlert: state.pit == null ? alert : BrakeAlert.none,
      brakeCoachPhase: coach.phase,
      brakeLearningLaps: coach.learnedLapCount,
    );
  }

  /// Corner edits made on the Corners screen during a session.
  void updateBrakeCorners(List<CornerBrakePoint> corners) =>
      _brakeCoach?.replaceCorners(corners);

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
              _hasDrivers &&
              tracker.hasStopped &&
              fix.speedKmh < rules.resumeSpeedKmh,
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
      currentStint: _hasDrivers ? _stints.current : null,
      pitResult: PitResult(
        stop: stop,
        untilWallMicros:
            wallNow + (rules?.pitResultHold.inMicroseconds ?? 10000000),
      ),
    );
    unawaited(_saveSession());
  }

  /// The end-of-lap sequence: the last sector's gap first (if the lap has
  /// more than one sector), then the whole lap's gap.
  LapFlash _flashFor(
    Lap lap,
    List<Lap> earlier,
    int wallNow,
    DeltaDisplaySettings display,
  ) {
    final racing = [
      for (final l in earlier)
        if (!lapIncludesPitStop(l, state.pitStops)) l,
    ];
    final isPitLap =
        lapIncludesPitStop(lap, state.pitStops) || state.pit != null;
    final delta = LapReferences.lapDeltaMicros(lap, racing);
    final lastIndex = lap.sectorMicros.length - 1;
    final lastTime = lastIndex >= 1 ? lap.sectorMicros[lastIndex] : null;
    final lastSector = lastTime == null
        ? null
        : SectorFlash(
            sectorIndex: lastIndex,
            sectorMicros: lastTime,
            deltaMicros: state.references.sectorDeltaMicros(
              lastIndex,
              lastTime,
              state.compareMode,
            ),
            untilWallMicros: wallNow + display.lastSectorHold.inMicroseconds,
          );
    final lastHold = lastSector == null
        ? 0
        : display.lastSectorHold.inMicroseconds;
    return LapFlash(
      lap: lap,
      deltaMicros: delta,
      isBest: !isPitLap && (delta == null || delta < 0),
      startedWallMicros: wallNow,
      lastSector: lastSector,
      lastSectorHoldMicros: lastHold,
      untilWallMicros: wallNow + lastHold + display.lapHold.inMicroseconds,
    );
  }

  /// The brake points as they stand, ready to be reviewed and saved as a
  /// profile from the Corners screen.
  BrakeProfile? _brakeProfileDraft(Session session) {
    final coach = _brakeCoach;
    final path = coach?.pathLatLng;
    if (coach == null || path == null) return null;
    final starting = ref.read(pendingSessionConfigProvider)?.brakeProfile;
    final date = session.startedAt.toLocal().toIso8601String().split('T').first;
    return BrakeProfile(
      id: starting?.id ?? 'brake-${session.id}',
      name:
          starting?.name ??
          '${session.trackName} – ${session.vehicleType.name} – $date',
      trackId: session.trackId,
      vehicleType: session.vehicleType,
      pathLatLng: path,
      corners: coach.corners,
    );
  }

  Future<void> _saveSession() async {
    final session = _session;
    if (session == null) return;
    final updated = session.withProgress(
      laps: state.laps,
      stints: _stints.stints,
      pitStops: state.pitStops,
      brakeProfile: _brakeProfileDraft(session),
      brakeMisses: _brakeCoach?.misses,
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
