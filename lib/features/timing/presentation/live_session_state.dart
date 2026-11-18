import 'package:lap_timer/features/gps/data/gps_source.dart';
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
  });

  /// Track to time on (must have a start/finish line).
  final Track track;

  /// Sector lines to use; null = whole lap is one sector.
  final SectorLayout? sectorLayout;

  /// Vehicle kind.
  final VehicleType vehicleType;

  /// What sector deltas compare against.
  final SectorCompareMode compareMode;
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
  });

  /// The lap just completed.
  final Lap lap;

  /// Gap to the previous best lap (negative = faster), if any.
  final int? deltaMicros;

  /// Whether it is the new best lap.
  final bool isBest;

  /// Wall-clock time (µs) until which the flash stays on screen.
  final int untilWallMicros;
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

  /// References derived from [laps] (best lap, best sectors).
  LapReferences get references =>
      LapReferences.from(laps, sectorCount: sectorCount);

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
  );
}
