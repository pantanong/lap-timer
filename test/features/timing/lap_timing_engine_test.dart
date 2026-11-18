import 'dart:math' as math;

import 'package:lap_timer/core/geo/local_point.dart';
import 'package:lap_timer/features/gps/domain/gps_fix.dart';
import 'package:lap_timer/features/gps/domain/simulated_track.dart';
import 'package:lap_timer/features/timing/domain/lap.dart';
import 'package:lap_timer/features/timing/domain/lap_comparison.dart';
import 'package:lap_timer/features/timing/domain/lap_timing_engine.dart';
import 'package:lap_timer/features/tracks/domain/gate_line.dart';
import 'package:test/test.dart';

/// A gate on the simulated track at [distance] metres, facing the direction
/// of travel (or with no direction when [withBearing] is false).
GateLine gateAt(
  SimulatedTrack track,
  double distance, {
  bool withBearing = true,
}) {
  final p = track.pointAt(distance);
  final ahead = track.pointAt(distance + 1) - p;
  final (lat, lon) = track.projection.toLatLng(p);
  final bearing = (math.atan2(ahead.x, ahead.y) * 180 / math.pi + 360) % 360;
  return GateLine(
    latitude: lat,
    longitude: lon,
    travelBearingDegrees: withBearing ? bearing : null,
  );
}

List<Lap> runLaps(
  SimulatedTrack track,
  double rateHz, {
  int laps = 3,
  bool withBearing = true,
}) {
  final engine = LapTimingEngine(
    startFinish: gateAt(track, 0, withBearing: withBearing),
    splits: [
      gateAt(track, track.lapLengthMetres / 3, withBearing: withBearing),
      gateAt(track, 2 * track.lapLengthMetres / 3, withBearing: withBearing),
    ],
  );
  final result = <Lap>[];
  for (final fix in track.drive(laps: laps, rateHz: rateHz)) {
    for (final event in engine.add(fix)) {
      if (event is LapCompleted) result.add(event.lap);
    }
  }
  return result;
}

void main() {
  final track = SimulatedTrack();
  // 100 Hz is effectively the "true" time for comparison.
  final reference = runLaps(track, 100);

  test('times every lap of the simulation', () {
    expect(reference, hasLength(3));
    expect(reference.map((l) => l.number), [1, 2, 3]);
  });

  test('sector times add up exactly to the lap time', () {
    for (final lap in reference) {
      expect(lap.sectorMicros, hasLength(3));
      expect(lap.hasAllSectors, isTrue);
      final sum = lap.sectorMicros.fold<int>(0, (a, b) => a + b!);
      expect(sum, lap.timeMicros);
    }
  });

  test('10 Hz GPS matches true lap time within 0.02 s', () {
    final laps = runLaps(track, 10);
    for (var i = 0; i < laps.length; i++) {
      final error = (laps[i].timeMicros - reference[i].timeMicros).abs();
      expect(error, lessThan(20000), reason: 'lap ${i + 1}');
    }
  });

  test('1 Hz phone GPS matches true lap time within 0.1 s', () {
    final laps = runLaps(track, 1);
    expect(laps, hasLength(3));
    for (var i = 0; i < laps.length; i++) {
      final error = (laps[i].timeMicros - reference[i].timeMicros).abs();
      expect(error, lessThan(100000), reason: 'lap ${i + 1}');
    }
  });

  test('lines set while standing (no direction) still time laps', () {
    final laps = runLaps(track, 10, withBearing: false);
    expect(laps, hasLength(3));
  });

  test('a line drawn on the map (two edge points) times laps', () {
    final proj = track.projection;
    // Start/finish drawn across the straight from y=-8 to y=+8 at x=0.
    final (latA, lonA) = proj.toLatLng(const LocalPoint(0, -8));
    final (latB, lonB) = proj.toLatLng(const LocalPoint(0, 8));
    final drawn = GateLine.fromEndpoints(latA, lonA, latB, lonB);
    expect(drawn.travelBearingDegrees, isNull);
    expect(drawn.widthMetres, closeTo(22, 0.01));
    final engine = LapTimingEngine(startFinish: drawn);
    final laps = <Lap>[];
    for (final fix in track.drive(laps: 2)) {
      for (final e in engine.add(fix)) {
        if (e is LapCompleted) laps.add(e.lap);
      }
    }
    expect(laps, hasLength(2));
    // The driving direction (east) was learned from the first crossing.
    expect(engine.learnedStartFinish.travelBearingDegrees, closeTo(90, 1));
  });

  test('driving the wrong way does not count', () {
    final engine = LapTimingEngine(startFinish: gateAt(track, 0));
    final reversed = track.drive(laps: 2).toList().reversed.toList();
    final events = <TimingEvent>[];
    for (var i = 0; i < reversed.length; i++) {
      final f = reversed[i];
      events.addAll(
        engine.add(
          GpsFix(
            timestampMicros: i * 100000,
            latitude: f.latitude,
            longitude: f.longitude,
            speedMetresPerSecond: f.speedMetresPerSecond,
          ),
        ),
      );
    }
    expect(events, isEmpty);
  });

  test('a parallel lane 15 m away does not trigger a 24 m wide line', () {
    final engine = LapTimingEngine(startFinish: gateAt(track, 0));
    final proj = track.projection;
    final events = <TimingEvent>[];
    for (var x = -100.0; x <= 100; x += 10) {
      // y = -15: a lane parallel to the straight, 15 m to the side.
      final (lat, lon) = proj.toLatLng(LocalPoint(x, -15));
      events.addAll(
        engine.add(
          GpsFix(
            timestampMicros: ((x + 100) * 100000).round(),
            latitude: lat,
            longitude: lon,
            speedMetresPerSecond: 15,
          ),
        ),
      );
    }
    expect(events, isEmpty);
  });

  group('LapReferences', () {
    const lapA = Lap(
      number: 1,
      startMicros: 0,
      endMicros: 150000000,
      sectorMicros: [50000000, 60000000, 40000000],
    );
    const lapB = Lap(
      number: 2,
      startMicros: 150000000,
      endMicros: 298000000,
      sectorMicros: [48000000, 62000000, 38000000],
    );
    final refs = LapReferences.from([lapA, lapB], sectorCount: 3);

    test('best lap and best sectors', () {
      expect(refs.bestLap, lapB);
      expect(refs.bestSectorMicros, [48000000, 60000000, 38000000]);
      expect(refs.optimalLapMicros, 146000000);
    });

    test('delta depends on the compare mode', () {
      // 49 s in S1: slower than best sector (48) and faster than... best
      // lap's S1 is also 48, so both are +1 s here.
      expect(
        refs.sectorDeltaMicros(1, 61000000, SectorCompareMode.bestLap),
        -1000000,
      );
      expect(
        refs.sectorDeltaMicros(1, 61000000, SectorCompareMode.bestSector),
        1000000,
      );
    });

    test('predicted lap = completed sectors + reference remainder', () {
      expect(
        refs.predictedLapMicros([47000000], SectorCompareMode.bestLap),
        47000000 + 62000000 + 38000000,
      );
    });
  });
}
