import 'package:lap_timer/features/gps/domain/simulated_track.dart';
import 'package:lap_timer/features/race/domain/pit_lane_tracker.dart';
import 'package:lap_timer/features/race/domain/pit_stop.dart';
import 'package:lap_timer/features/race/domain/race_rules.dart';
import 'package:lap_timer/features/race/domain/stint.dart';
import 'package:lap_timer/features/tracks/data/simulator_track_preset.dart';
import 'package:test/test.dart';

void main() {
  final sim = SimulatedTrack();
  final preset = simulatorTrackPreset(sim);

  PitLaneTracker newTracker() =>
      PitLaneTracker(pitEntry: preset.pitEntry!, pitExit: preset.pitExit!);

  test('detects one pit stop with the stop time included', () {
    final tracker = newTracker();
    final stops = <PitStop>[];
    var entries = 0;
    for (final fix in sim.drive(
      laps: 3,
      pitStopAtCrossings: {2},
      pitStopSeconds: 30,
    )) {
      for (final e in tracker.add(fix)) {
        if (e is PitEntered) entries++;
        if (e is PitExited) stops.add(e.stop);
      }
    }
    expect(entries, 1);
    expect(stops, hasLength(1));
    final stop = stops.single;
    expect(stop.stopped, isTrue);
    // 240 m at 50 km/h ≈ 17.3 s, plus the 30 s stop.
    expect(stop.durationMicros / 1e6, closeTo(47.3, 0.5));
    expect(stop.maxSpeedKmh, closeTo(50, 0.01));
  });

  test('laps on the racing line beside the pit lane never enter pit mode', () {
    final tracker = newTracker();
    final events = [for (final fix in sim.drive(laps: 3)) ...tracker.add(fix)];
    expect(events, isEmpty);
  });

  test('projected pit time at exit uses remaining distance and speed', () {
    final tracker = newTracker();
    int? projected;
    for (final fix in sim.drive(laps: 2, pitStopAtCrossings: {1})) {
      tracker.add(fix);
      if (tracker.phase == PitPhase.inPitLane && fix.speedKmh > 10) {
        projected = tracker.projectedPitMicrosAtExit(
          fix.timestampMicros,
          fix.speedKmh,
        );
      }
    }
    expect(projected, isNotNull);
  });

  group('StintPlan', () {
    test('solo driver: Nong(1) → Nong(2)', () {
      final plan = StintPlan.start(const ['Nong']);
      expect(plan.current.label, 'Nong(1)');
      expect(plan.nextStint(sameDriver: false).label, 'Nong(2)');
      final next = plan.advance(sameDriver: false, atMicros: 100);
      expect(next.current.label, 'Nong(2)');
    });

    test('endurance: rotates the roster; Same driver keeps the driver', () {
      var plan = StintPlan.start(const ['Nong', 'Ake']);
      plan = plan.advance(sameDriver: false, atMicros: 100);
      expect(plan.current.label, 'Ake(1)');
      plan = plan.advance(sameDriver: true, atMicros: 200);
      expect(plan.current.label, 'Ake(2)');
      plan = plan.advance(sameDriver: false, atMicros: 300);
      expect(plan.current.label, 'Nong(2)');
      expect(plan.stintAt(150).label, 'Ake(1)');
      expect(plan.stintAt(50).label, 'Nong(1)');
    });
  });

  test('RaceRules JSON round-trip', () {
    const rules = RaceRules(
      id: 'r1',
      name: 'Club race',
      minimumPitTime: Duration(seconds: 75),
      requiredPitStops: 2,
    );
    final decoded = RaceRules.tryFromJson(rules.toJson());
    expect(decoded?.minimumPitTime, const Duration(seconds: 75));
    expect(decoded?.requiredPitStops, 2);
    expect(decoded?.pitSpeedLimitKmh, 60);
  });
}
