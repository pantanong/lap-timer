import 'package:lap_timer/features/brake_coach/domain/brake_alert.dart';
import 'package:lap_timer/features/brake_coach/domain/brake_coach.dart';
import 'package:lap_timer/features/brake_coach/domain/brake_profile.dart';
import 'package:lap_timer/features/gps/data/gps_source.dart';
import 'package:lap_timer/features/race/domain/pit_stop.dart';
import 'package:lap_timer/features/race/domain/race_rules.dart';
import 'package:lap_timer/features/race/domain/stint.dart';
import 'package:lap_timer/features/sessions/domain/session.dart';
import 'package:lap_timer/features/timing/domain/lap.dart';
import 'package:lap_timer/features/timing/domain/lap_comparison.dart';
import 'package:lap_timer/features/tracks/domain/track.dart';
import 'package:meta/meta.dart';

/// What the user chose on the New Session screen.
@immutable
class LiveSessionConfig {
  /// Creates a configuration.
  const LiveSessionConfig({
    required this.track,
    required this.vehicleType,
    this.sectorLayout,
    this.compareMode = SectorCompareMode.bestLap,
    this.raceRules,
    this.drivers = const [],
    this.brakeCoach,
    this.brakeProfile,
    this.deltaDisplay = const DeltaDisplaySettings(),
  });

  /// Track to time on (must have a start/finish line).
  final Track track;

  /// Sector lines to use; null = whole lap is one sector.
  final SectorLayout? sectorLayout;

  /// Vehicle kind.
  final VehicleType vehicleType;

  /// What sector deltas compare against.
  final SectorCompareMode compareMode;

  /// Race rules (pit lane limit, minimum pit time); null = no pit mode.
  final RaceRules? raceRules;

  /// Drivers in driving order; empty = one unnamed driver.
  final List<String> drivers;

  /// Brake coach options; null = brake coach off.
  final BrakeCoachSettings? brakeCoach;

  /// Saved brake profile to start from (skips the learning laps).
  final BrakeProfile? brakeProfile;

  /// How long the big number shows sector and lap gaps.
  final DeltaDisplaySettings deltaDisplay;
}

/// How long the big number shows a gap instead of the running lap time.
@immutable
class DeltaDisplaySettings {
  /// Creates settings; defaults: 5 s per sector, then at the end of a lap
  /// 2 s for the last sector followed by 5 s for the whole lap.
  const DeltaDisplaySettings({
    this.sectorHold = const Duration(seconds: 5),
    this.lastSectorHold = const Duration(seconds: 2),
    this.lapHold = const Duration(seconds: 5),
  });

  /// After each sector during the lap.
  final Duration sectorHold;

  /// At the end of the lap: the last sector's gap, first.
  final Duration lastSectorHold;

  /// At the end of the lap: the whole lap's gap, after the last sector.
  final Duration lapHold;
}

/// A just-completed sector, shown big for a few seconds.
@immutable
class SectorFlash {
  /// Creates the flash.
  const SectorFlash({
    required this.sectorIndex,
    required this.sectorMicros,
    required this.deltaMicros,
    required this.untilWallMicros,
  });

  /// 0-based sector.
  final int sectorIndex;

  /// Sector time.
  final int sectorMicros;

  /// Gap to the reference (negative = faster), if any.
  final int? deltaMicros;

  /// Wall-clock time (µs) until which it is shown.
  final int untilWallMicros;
}

/// What the pit lane screen shows.
@immutable
class PitView {
  /// Creates the view state.
  const PitView({
    required this.entryMicros,
    this.maxSpeedKmh = 0,
    this.projectedExitPitMicros,
    this.showNextDriver = false,
    this.nextStintLabel = '',
    this.sameDriver = false,
  });

  /// Pit entry crossing (GPS time, µs).
  final int entryMicros;

  /// Highest speed since the entry.
  final double maxSpeedKmh;

  /// Expected total pit time at the exit line at the current speed.
  final int? projectedExitPitMicros;

  /// Show the next driver's name instead of the speed (car stopped, not
  /// yet back above the resume speed).
  final bool showNextDriver;

  /// e.g. "Nong(2)".
  final String nextStintLabel;

  /// "Same driver" was pressed during this stop.
  final bool sameDriver;

  /// Returns a copy with the given fields replaced.
  PitView copyWith({
    double? maxSpeedKmh,
    int? projectedExitPitMicros,
    bool clearProjection = false,
    bool? showNextDriver,
    String? nextStintLabel,
    bool? sameDriver,
  }) => PitView(
    entryMicros: entryMicros,
    maxSpeedKmh: maxSpeedKmh ?? this.maxSpeedKmh,
    projectedExitPitMicros: clearProjection
        ? null
        : projectedExitPitMicros ?? this.projectedExitPitMicros,
    showNextDriver: showNextDriver ?? this.showNextDriver,
    nextStintLabel: nextStintLabel ?? this.nextStintLabel,
    sameDriver: sameDriver ?? this.sameDriver,
  );
}

/// A finished pit stop shown on screen for a few seconds after the exit.
@immutable
class PitResult {
  /// Creates the result banner.
  const PitResult({required this.stop, required this.untilWallMicros});

  /// The pit stop.
  final PitStop stop;

  /// Wall-clock time (µs) until which it stays on screen.
  final int untilWallMicros;
}

/// Lifecycle of a live session.
enum LiveSessionStatus {
  /// Opening the GPS source.
  preparing,

  /// Timing.
  running,

  /// The GPS source could not start.
  failed,

  /// Ended by the user; data saved.
  ended,
}

/// The last completed lap, shown large for a few seconds.
@immutable
class LapFlash {
  /// Creates the flash.
  const LapFlash({
    required this.lap,
    required this.deltaMicros,
    required this.isBest,
    required this.untilWallMicros,
    this.startedWallMicros = 0,
    this.lastSector,
    this.lastSectorHoldMicros = 0,
  });

  /// The lap just completed.
  final Lap lap;

  /// Gap to the previous best lap (negative = faster), if any.
  final int? deltaMicros;

  /// Whether it is the new best lap.
  final bool isBest;

  /// Wall-clock time (µs) until which the flash stays on screen.
  final int untilWallMicros;

  /// Wall-clock time (µs) the lap ended.
  final int startedWallMicros;

  /// The last sector of the lap, shown first (null with one sector).
  final SectorFlash? lastSector;

  /// How long the last sector is shown before the lap gap.
  final int lastSectorHoldMicros;
}

/// Immutable snapshot of a live timing session.
@immutable
class LiveSessionState {
  /// Creates a state.
  const LiveSessionState({
    required this.status,
    required this.sectorCount,
    required this.compareMode,
    this.failure,
    this.laps = const [],
    this.lapNumber = 1,
    this.currentLapStartMicros,
    this.currentSectorIndex = 0,
    this.currentLapSectors = const [],
    this.currentSectorStartMicros,
    this.lastFixMicros,
    this.lastFixWallMicros,
    this.speedKmh,
    this.gpsRateHz,
    this.flash,
    this.raceRules,
    this.pit,
    this.pitResult,
    this.pitStops = const [],
    this.currentStint,
    this.brakeAlert = BrakeAlert.none,
    this.brakeCoachPhase,
    this.brakeLearningLaps = 0,
    this.brakeLearningLapsNeeded = 0,
    this.sectorFlash,
    this.liveDeltaMicros,
  });

  /// Lifecycle step.
  final LiveSessionStatus status;

  /// Why the GPS failed, when [status] is failed.
  final GpsFailure? failure;

  /// Sectors per lap.
  final int sectorCount;

  /// Active comparison mode.
  final SectorCompareMode compareMode;

  /// Completed laps.
  final List<Lap> laps;

  /// Number of the lap being driven.
  final int lapNumber;

  /// Start of the lap in progress (GPS time, µs); null before the first
  /// start/finish crossing.
  final int? currentLapStartMicros;

  /// 0-based sector being driven.
  final int currentSectorIndex;

  /// Sector times already completed in this lap.
  final List<int?> currentLapSectors;

  /// Start of the sector being driven (GPS time, µs).
  final int? currentSectorStartMicros;

  /// GPS time of the latest fix.
  final int? lastFixMicros;

  /// Wall-clock time the latest fix arrived; together with
  /// [lastFixMicros] it lets the running clock tick between fixes.
  final int? lastFixWallMicros;

  /// Latest speed.
  final double? speedKmh;

  /// Measured GPS rate.
  final double? gpsRateHz;

  /// Lap-complete banner, if showing.
  final LapFlash? flash;

  /// Race rules in force, if any.
  final RaceRules? raceRules;

  /// Set while the car is in the pit lane.
  final PitView? pit;

  /// Last pit stop, shown for a few seconds after the exit.
  final PitResult? pitResult;

  /// Completed pit stops.
  final List<PitStop> pitStops;

  /// Who is driving now, e.g. Nong(1).
  final Stint? currentStint;

  /// Yellow / red brake alert to show now.
  final BrakeAlert brakeAlert;

  /// Learning or active; null when the brake coach is off.
  final BrakeCoachPhase? brakeCoachPhase;

  /// Learning laps recorded so far.
  final int brakeLearningLaps;

  /// Learning laps needed before alerts start.
  final int brakeLearningLapsNeeded;

  /// The sector just completed, shown big for a few seconds.
  final SectorFlash? sectorFlash;

  /// Live gap to the best lap at the current position (negative = ahead);
  /// null without a best lap, before the first crossing or off the line.
  final int? liveDeltaMicros;

  /// Laps without a pit stop: the only ones that count for best times.
  List<Lap> get racingLaps => [
    for (final lap in laps)
      if (!lapIncludesPitStop(lap, pitStops)) lap,
  ];

  /// References derived from [racingLaps] (best lap, best sectors).
  LapReferences get references =>
      LapReferences.from(racingLaps, sectorCount: sectorCount);

  /// Converts wall-clock [nowWallMicros] to estimated GPS time.
  int? gpsNowMicros(int nowWallMicros) {
    final fix = lastFixMicros;
    final wall = lastFixWallMicros;
    if (fix == null || wall == null) return null;
    // Never extrapolate more than 2 s past the last fix (GPS lost).
    final gap = (nowWallMicros - wall).clamp(0, 2000000);
    return fix + gap;
  }

  /// Returns a copy with the given fields replaced. [clearFlash] removes
  /// the lap banner.
  LiveSessionState copyWith({
    LiveSessionStatus? status,
    GpsFailure? failure,
    List<Lap>? laps,
    int? lapNumber,
    int? currentLapStartMicros,
    int? currentSectorIndex,
    List<int?>? currentLapSectors,
    int? currentSectorStartMicros,
    int? lastFixMicros,
    int? lastFixWallMicros,
    double? speedKmh,
    double? gpsRateHz,
    SectorCompareMode? compareMode,
    LapFlash? flash,
    bool clearFlash = false,
    PitView? pit,
    bool clearPit = false,
    PitResult? pitResult,
    bool clearPitResult = false,
    List<PitStop>? pitStops,
    Stint? currentStint,
    BrakeAlert? brakeAlert,
    BrakeCoachPhase? brakeCoachPhase,
    int? brakeLearningLaps,
    SectorFlash? sectorFlash,
    bool clearSectorFlash = false,
    int? liveDeltaMicros,
    bool clearLiveDelta = false,
  }) => LiveSessionState(
    status: status ?? this.status,
    failure: failure ?? this.failure,
    sectorCount: sectorCount,
    compareMode: compareMode ?? this.compareMode,
    laps: laps ?? this.laps,
    lapNumber: lapNumber ?? this.lapNumber,
    currentLapStartMicros: currentLapStartMicros ?? this.currentLapStartMicros,
    currentSectorIndex: currentSectorIndex ?? this.currentSectorIndex,
    currentLapSectors: currentLapSectors ?? this.currentLapSectors,
    currentSectorStartMicros:
        currentSectorStartMicros ?? this.currentSectorStartMicros,
    lastFixMicros: lastFixMicros ?? this.lastFixMicros,
    lastFixWallMicros: lastFixWallMicros ?? this.lastFixWallMicros,
    speedKmh: speedKmh ?? this.speedKmh,
    gpsRateHz: gpsRateHz ?? this.gpsRateHz,
    flash: clearFlash ? null : (flash ?? this.flash),
    raceRules: raceRules,
    pit: clearPit ? null : (pit ?? this.pit),
    pitResult: clearPitResult ? null : (pitResult ?? this.pitResult),
    pitStops: pitStops ?? this.pitStops,
    currentStint: currentStint ?? this.currentStint,
    brakeAlert: brakeAlert ?? this.brakeAlert,
    brakeCoachPhase: brakeCoachPhase ?? this.brakeCoachPhase,
    brakeLearningLaps: brakeLearningLaps ?? this.brakeLearningLaps,
    brakeLearningLapsNeeded: brakeLearningLapsNeeded,
    sectorFlash: clearSectorFlash ? null : (sectorFlash ?? this.sectorFlash),
    liveDeltaMicros: clearLiveDelta
        ? null
        : (liveDeltaMicros ?? this.liveDeltaMicros),
  );
}
