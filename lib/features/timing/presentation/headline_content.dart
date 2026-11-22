import 'package:lap_timer/features/timing/domain/lap.dart';
import 'package:lap_timer/features/timing/presentation/live_session_state.dart';

/// What the big number on the live screen shows right now.
sealed class HeadlineContent {
  const HeadlineContent();
}

/// The running lap time (the normal state).
final class RunningLapHeadline extends HeadlineContent {
  /// Creates the content; [elapsedMicros] is null before the first
  /// start/finish crossing.
  const RunningLapHeadline(this.elapsedMicros);

  /// Time since the lap started.
  final int? elapsedMicros;
}

/// The gap of a sector that has just been completed, next to a time.
final class SectorGapHeadline extends HeadlineContent {
  /// Creates the content.
  const SectorGapHeadline(
    this.sector, {
    required this.timeMicros,
    this.finishedLap,
  });

  /// The sector.
  final SectorFlash sector;

  /// Time shown before the gap: the running lap time during a lap, the
  /// finished lap's time at the end of a lap. Null before the first
  /// start/finish crossing.
  final int? timeMicros;

  /// Set at the end of a lap (the gap of its last sector).
  final LapFlash? finishedLap;
}

/// The gap of the lap that has just been completed.
final class LapGapHeadline extends HeadlineContent {
  /// Creates the content.
  const LapGapHeadline(this.flash);

  /// The finished lap.
  final LapFlash flash;
}

/// Decides the big number at wall time [wallNowMicros]:
///
/// - after a sector: its gap, for the sector hold time;
/// - after a lap: the last sector's gap (short), then the lap's gap;
/// - otherwise: the running lap time at GPS time [gpsNowMicros].
HeadlineContent headlineContentAt(
  LiveSessionState state, {
  required int wallNowMicros,
  required int? gpsNowMicros,
}) {
  final start = state.currentLapStartMicros;
  final now = gpsNowMicros;
  final elapsed = start == null || now == null ? null : now - start;
  final flash = state.flash;
  if (flash != null && wallNowMicros <= flash.untilWallMicros) {
    final sinceEnd = wallNowMicros - flash.startedWallMicros;
    final last = flash.lastSector;
    if (last != null && sinceEnd < flash.lastSectorHoldMicros) {
      return SectorGapHeadline(
        last,
        timeMicros: flash.lap.timeMicros,
        finishedLap: flash,
      );
    }
    return LapGapHeadline(flash);
  }
  final sector = state.sectorFlash;
  if (sector != null && wallNowMicros <= sector.untilWallMicros) {
    return SectorGapHeadline(sector, timeMicros: elapsed);
  }
  return RunningLapHeadline(elapsed);
}

/// The lap whose time the side panel should show instead of the predicted
/// lap (during the end-of-lap sequence), if any.
Lap? finishedLapShown(HeadlineContent content, LiveSessionState state) =>
    switch (content) {
      LapGapHeadline(:final flash) => flash.lap,
      SectorGapHeadline() when state.flash != null => state.flash?.lap,
      _ => null,
    };
