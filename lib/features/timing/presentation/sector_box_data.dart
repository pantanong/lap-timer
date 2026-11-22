import 'package:lap_timer/features/timing/domain/lap.dart';
import 'package:lap_timer/features/timing/domain/lap_comparison.dart';
import 'package:lap_timer/features/timing/presentation/live_session_state.dart';
import 'package:meta/meta.dart';

/// State of one sector box on the live screen.
enum SectorBoxKind {
  /// Completed this lap: shows its time and delta.
  done,

  /// Being driven now: shows the running sector time.
  running,

  /// Not reached yet.
  pending,
}

/// Everything one sector box needs to render (no logic left for widgets).
@immutable
class SectorBoxData {
  /// Creates box data.
  const SectorBoxData({
    required this.index,
    required this.kind,
    this.timeMicros,
    this.deltaMicros,
  });

  /// 0-based sector index.
  final int index;

  /// Done / running / pending.
  final SectorBoxKind kind;

  /// Sector time (done) or running time (running).
  final int? timeMicros;

  /// Gap to the reference (done only); negative = faster.
  final int? deltaMicros;
}

/// Builds the sector boxes for the live screen at GPS time [gpsNowMicros].
///
/// Until the first sector of a new lap is completed, the boxes keep showing
/// the previous lap, compared with the references as they were *before*
/// that lap.
List<SectorBoxData> buildSectorBoxes(
  LiveSessionState state,
  int? gpsNowMicros,
) {
  // The previous lap stays visible until the first sector of the new lap
  // is completed (then the new lap's boxes take over).
  final flash = state.flash;
  if (flash != null) return _finishedLapBoxes(state, flash.lap);
  final laps = state.laps;
  final noSectorYet = state.currentLapSectors.isEmpty;
  if (noSectorYet && laps.isNotEmpty && state.currentLapStartMicros != null) {
    return _finishedLapBoxes(state, laps.last);
  }

  final refs = state.references;
  final boxes = <SectorBoxData>[];
  for (var i = 0; i < state.sectorCount; i++) {
    if (i < state.currentLapSectors.length) {
      final t = state.currentLapSectors[i];
      boxes.add(
        SectorBoxData(
          index: i,
          kind: SectorBoxKind.done,
          timeMicros: t,
          deltaMicros: t == null
              ? null
              : refs.sectorDeltaMicros(i, t, state.compareMode),
        ),
      );
    } else if (i == state.currentSectorIndex &&
        state.currentLapStartMicros != null) {
      final start = state.currentSectorStartMicros;
      boxes.add(
        SectorBoxData(
          index: i,
          kind: SectorBoxKind.running,
          timeMicros: start == null || gpsNowMicros == null
              ? null
              : gpsNowMicros - start,
        ),
      );
    } else {
      boxes.add(SectorBoxData(index: i, kind: SectorBoxKind.pending));
    }
  }
  return boxes;
}

List<SectorBoxData> _finishedLapBoxes(LiveSessionState state, Lap lap) {
  final earlier = [
    for (final l in state.laps)
      if (l.number != lap.number) l,
  ];
  final refs = LapReferences.from(earlier, sectorCount: state.sectorCount);
  return [
    for (var i = 0; i < state.sectorCount; i++)
      SectorBoxData(
        index: i,
        kind: SectorBoxKind.done,
        timeMicros: i < lap.sectorMicros.length ? lap.sectorMicros[i] : null,
        deltaMicros: switch (i < lap.sectorMicros.length
            ? lap.sectorMicros[i]
            : null) {
          final int t => refs.sectorDeltaMicros(i, t, state.compareMode),
          null => null,
        },
      ),
  ];
}
