import 'package:lap_timer/core/geo/local_point.dart';
import 'package:lap_timer/features/gps/domain/gps_fix.dart';
import 'package:lap_timer/features/gps/domain/simulated_track.dart';
import 'package:lap_timer/features/timing/domain/live_delta.dart';
import 'package:test/test.dart';

void main() {
  final sim = SimulatedTrack();
  // One lap from the line back to the line, 10 Hz.
  final lap = sim.drive(laps: 1, runUpMetres: 0, runOutMetres: 0).toList();
  final lapMicros = lap.last.timestampMicros - lap.first.timestampMicros;

  LiveDeltaTracker newTracker() => LiveDeltaTracker(
    LocalProjection(
      originLatitude: lap.first.latitude,
      originLongitude: lap.first.longitude,
    ),
  );

  /// Drives [fixes] as a lap starting at [startMicros], with every time
  /// stretched by [timeFactor]; returns the live deltas.
  List<int> driveLap(
    LiveDeltaTracker tracker,
    List<GpsFix> fixes, {
    required int startMicros,
    double timeFactor = 1,
  }) {
    tracker.startLap(startMicros);
    final deltas = <int>[];
    for (final f in fixes) {
      final t = startMicros + (f.timestampMicros * timeFactor).round();
      final d = tracker.add(
        latitude: f.latitude,
        longitude: f.longitude,
        timeMicros: t,
      );
      if (d != null) deltas.add(d);
    }
    return deltas;
  }

  test('no delta before there is a best lap', () {
    final tracker = newTracker();
    expect(driveLap(tracker, lap, startMicros: 0), isEmpty);
  });

  test('same lap again: live delta stays near zero', () {
    final tracker = newTracker();
    driveLap(tracker, lap, startMicros: 0);
    tracker.completeLap(lapMicros: lapMicros, isRacingLap: true);
    final deltas = driveLap(tracker, lap, startMicros: lapMicros);
    expect(deltas, isNotEmpty);
    for (final d in deltas) {
      expect(d.abs(), lessThan(20000), reason: '$d µs');
    }
  });

  test('5 % slower everywhere: delta grows to 5 % of the lap time', () {
    final tracker = newTracker();
    driveLap(tracker, lap, startMicros: 0);
    tracker.completeLap(lapMicros: lapMicros, isRacingLap: true);
    final deltas = driveLap(
      tracker,
      lap,
      startMicros: lapMicros,
      timeFactor: 1.05,
    );
    expect(deltas.last, closeTo(lapMicros * 0.05, 100000));
    // Halfway through the lap the gap is about half of that.
    final half = deltas[deltas.length ~/ 2];
    expect(half, closeTo(lapMicros * 0.025, 300000));
  });

  test('a slower lap or a pit lap never replaces the reference', () {
    final tracker = newTracker();
    driveLap(tracker, lap, startMicros: 0);
    tracker.completeLap(lapMicros: lapMicros, isRacingLap: true);
    driveLap(tracker, lap, startMicros: lapMicros, timeFactor: 1.1);
    tracker.completeLap(lapMicros: lapMicros * 2, isRacingLap: true);
    driveLap(tracker, lap, startMicros: lapMicros * 3, timeFactor: 0.9);
    tracker.completeLap(lapMicros: lapMicros ~/ 2, isRacingLap: false);
    expect(tracker.referenceLapMicros, lapMicros);
  });
}
