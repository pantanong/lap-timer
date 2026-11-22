import 'package:lap_timer/features/timing/domain/lap.dart';
import 'package:lap_timer/features/timing/domain/lap_comparison.dart';
import 'package:lap_timer/features/timing/presentation/headline_content.dart';
import 'package:lap_timer/features/timing/presentation/live_session_state.dart';
import 'package:test/test.dart';

void main() {
  const s = 1000000; // one second in microseconds
  const lap = Lap(
    number: 2,
    startMicros: 0,
    endMicros: 150 * s,
    sectorMicros: [50 * s, 60 * s, 40 * s],
  );
  const lastSector = SectorFlash(
    sectorIndex: 2,
    sectorMicros: 40 * s,
    deltaMicros: -780000,
    untilWallMicros: 102 * s,
  );
  // Lap ended at wall time 100 s: last sector 2 s, then lap gap 5 s.
  const flash = LapFlash(
    lap: lap,
    deltaMicros: -3800000,
    isBest: true,
    startedWallMicros: 100 * s,
    lastSector: lastSector,
    lastSectorHoldMicros: 2 * s,
    untilWallMicros: 107 * s,
  );

  LiveSessionState stateWith({LapFlash? lapFlash, SectorFlash? sector}) =>
      LiveSessionState(
        status: LiveSessionStatus.running,
        sectorCount: 3,
        compareMode: SectorCompareMode.bestLap,
        currentLapStartMicros: 200 * s,
        flash: lapFlash,
        sectorFlash: sector,
      );

  test('end of lap: last sector first, then the lap gap, then running', () {
    final state = stateWith(lapFlash: flash);
    HeadlineContent at(int wallSeconds) => headlineContentAt(
      state,
      wallNowMicros: wallSeconds * s,
      gpsNowMicros: 210 * s,
    );
    expect(at(101), isA<SectorGapHeadline>());
    expect((at(101) as SectorGapHeadline).sector.sectorIndex, 2);
    expect(at(103), isA<LapGapHeadline>());
    expect(at(106), isA<LapGapHeadline>());
    expect(at(108), isA<RunningLapHeadline>());
    expect((at(108) as RunningLapHeadline).elapsedMicros, 10 * s);
  });

  test('a sector gap shows for its hold time', () {
    const sector = SectorFlash(
      sectorIndex: 1,
      sectorMicros: 60 * s,
      deltaMicros: -2750000,
      untilWallMicros: 55 * s,
    );
    final state = stateWith(sector: sector);
    expect(
      headlineContentAt(state, wallNowMicros: 52 * s, gpsNowMicros: 0),
      isA<SectorGapHeadline>(),
    );
    expect(
      headlineContentAt(state, wallNowMicros: 56 * s, gpsNowMicros: 0),
      isA<RunningLapHeadline>(),
    );
  });

  test('the side panel shows the finished lap during the end sequence', () {
    final state = stateWith(lapFlash: flash);
    final content = headlineContentAt(
      state,
      wallNowMicros: 101 * s,
      gpsNowMicros: 0,
    );
    expect(finishedLapShown(content, state), lap);
  });
}
