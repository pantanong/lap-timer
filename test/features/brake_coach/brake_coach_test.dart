import 'dart:math' as math;

import 'package:lap_timer/core/geo/local_point.dart';
import 'package:lap_timer/features/brake_coach/domain/brake_alert.dart';
import 'package:lap_timer/features/brake_coach/domain/brake_coach.dart';
import 'package:lap_timer/features/brake_coach/domain/brake_detection.dart';
import 'package:lap_timer/features/brake_coach/domain/brake_learning.dart';
import 'package:lap_timer/features/brake_coach/domain/brake_profile.dart';
import 'package:lap_timer/features/brake_coach/domain/lap_trace.dart';
import 'package:lap_timer/features/gps/domain/simulated_track.dart';
import 'package:lap_timer/features/sessions/domain/session.dart';
import 'package:lap_timer/features/timing/domain/lap_timing_engine.dart';
import 'package:lap_timer/features/tracks/data/simulator_track_preset.dart';
import 'package:test/test.dart';

/// One lap of the simulator as a trace (odometer from the start line).
LapTrace simLapTrace(SimulatedTrack sim, double rateHz) {
  final proj = sim.projection;
  final samples = <TraceSample>[];
  LocalPoint? last;
  var odo = 0.0;
  // Skip the 50 m run-up: start at the line.
  for (final fix in sim.drive(laps: 1, rateHz: rateHz, runOutMetres: 0)) {
    final p = proj.toLocal(fix.latitude, fix.longitude);
    if (samples.isEmpty && p.x < 0) continue;
    // The first sample is a little past the line: start the odometer there.
    if (last == null) odo = p.x;
    if (last != null) odo += p.distanceTo(last);
    last = p;
    samples.add(
      TraceSample(
        timeMicros: fix.timestampMicros,
        distanceMetres: odo,
        speedMetresPerSecond: fix.speedMetresPerSecond,
        point: p,
      ),
    );
  }
  return LapTrace(samples);
}

/// A synthetic straight-line "corner": cruise at 40 m/s, brake at
/// [brakeAt] with [decelG] down to [minSpeed], accelerate at 0.4 g, and
/// finish with [extraSeconds] of slow driving (makes the lap slower
/// without touching the corner).
LapTrace syntheticLap({
  required double brakeAt,
  double decelG = 0.9,
  double minSpeed = 20,
  double extraSeconds = 0,
}) {
  const dt = 0.1;
  final samples = <TraceSample>[];
  var d = 0.0;
  var v = 40.0;
  var t = 0.0;
  var phase = 0; // 0 cruise, 1 braking, 2 accelerating
  while (d < 1000) {
    samples.add(
      TraceSample(
        timeMicros: (t * 1e6).round(),
        distanceMetres: d,
        speedMetresPerSecond: v,
        point: LocalPoint(d, 0),
      ),
    );
    if (phase == 0 && d >= brakeAt) phase = 1;
    if (phase == 1) {
      v -= decelG * gravity * dt;
      if (v <= minSpeed) {
        v = minSpeed;
        phase = 2;
      }
    } else if (phase == 2) {
      v = math.min(40, v + 0.4 * gravity * dt);
    }
    d += v * dt;
    t += dt;
  }
  t += extraSeconds;
  samples.add(
    TraceSample(
      timeMicros: (t * 1e6).round(),
      distanceMetres: d + 1,
      speedMetresPerSecond: v,
      point: LocalPoint(d + 1, 0),
    ),
  );
  return LapTrace(samples);
}

void main() {
  final sim = SimulatedTrack();
  const detection = BrakeDetectionSettings();

  group('detectBrakeEvents', () {
    test('finds both simulator brake points within 5 m at 10 Hz', () {
      final events = detectBrakeEvents(simLapTrace(sim, 10), detection);
      final truth = sim.brakePointDistances;
      expect(events, hasLength(2));
      for (var i = 0; i < 2; i++) {
        expect(events[i].onsetDistanceMetres, closeTo(truth[i], 5));
      }
    });

    test('still finds them within 45 m at 1 Hz (phone GPS)', () {
      final events = detectBrakeEvents(simLapTrace(sim, 1), detection);
      final truth = sim.brakePointDistances;
      expect(events, hasLength(2));
      for (var i = 0; i < 2; i++) {
        expect(events[i].onsetDistanceMetres, closeTo(truth[i], 45));
      }
    });

    test('lifting off (0.15 g) is not braking', () {
      final lap = syntheticLap(brakeAt: 300, decelG: 0.15);
      expect(detectBrakeEvents(lap, detection), isEmpty);
    });
  });

  group('learnBrakePoints', () {
    final projection = LocalProjection(originLatitude: 0, originLongitude: 0);

    LearningLap lap(int n, LapTrace trace) => LearningLap(
      lapNumber: n,
      lapTimeMicros: trace.samples.last.timeMicros,
      trace: trace,
    );

    test('Method 1 uses the fastest lap', () {
      final laps = [
        lap(1, syntheticLap(brakeAt: 300, extraSeconds: 2)),
        lap(2, syntheticLap(brakeAt: 290)),
      ];
      final learned = learnBrakePoints(
        laps: laps,
        detection: detection,
        method: BrakeLearningMethod.fastestLap,
        projection: projection,
      );
      expect(learned?.corners.single.sourceLapNumber, 2);
      expect(learned?.corners.single.brakeDistanceMetres, closeTo(290, 5));
    });

    test('Method 2 takes a later point from a slower lap if the corner '
        'was as good', () {
      final laps = [
        // Fastest lap overall, brakes at 290.
        lap(1, syntheticLap(brakeAt: 290)),
        // Slower lap (time lost elsewhere) but brakes 15 m later, harder,
        // same minimum speed: a better corner.
        lap(2, syntheticLap(brakeAt: 305, decelG: 1.1, extraSeconds: 3)),
      ];
      final learned = learnBrakePoints(
        laps: laps,
        detection: detection,
        method: BrakeLearningMethod.deepestValid,
        projection: projection,
      );
      expect(learned?.corners.single.sourceLapNumber, 2);
      expect(learned?.corners.single.brakeDistanceMetres, closeTo(305, 5));
    });

    test('Method 2 rejects a later point that ruined the corner', () {
      final laps = [
        lap(1, syntheticLap(brakeAt: 290)),
        // Braked later but overshot: much lower minimum speed.
        lap(2, syntheticLap(brakeAt: 305, decelG: 1.1, minSpeed: 14)),
      ];
      final learned = learnBrakePoints(
        laps: laps,
        detection: detection,
        method: BrakeLearningMethod.deepestValid,
        projection: projection,
      );
      expect(learned?.corners.single.sourceLapNumber, 1);
    });
  });

  test('coach learns for 3 laps, then shows yellow then red before each '
      'brake point', () {
    final preset = simulatorTrackPreset(sim);
    final sf = preset.startFinish!;
    final coach = BrakeCoach(
      settings: const BrakeCoachSettings(),
      projection: LocalProjection(
        originLatitude: sf.latitude,
        originLongitude: sf.longitude,
      ),
    );
    final engine = LapTimingEngine(startFinish: sf);
    final phasesOnLap5 = <BrakeAlertPhase>[];
    for (final fix in sim.drive(laps: 5)) {
      for (final e in engine.add(fix)) {
        if (e is LapCompleted) {
          coach.completeLap(
            lapNumber: e.lap.number,
            lapTimeMicros: e.lap.timeMicros,
            isRacingLap: true,
          );
        }
        if (e is LapStarted) coach.startLap();
      }
      final alert = coach.addFix(fix);
      if (engine.currentLapNumber == 5) phasesOnLap5.add(alert.phase);
    }
    expect(coach.phase, BrakeCoachPhase.active);
    expect(coach.corners, hasLength(2));
    // Yellow comes before red, and red appears for both corners.
    final changes = <BrakeAlertPhase>[];
    for (final p in phasesOnLap5) {
      if (changes.isEmpty || changes.last != p) changes.add(p);
    }
    expect(changes.where((p) => p == BrakeAlertPhase.brakeNow), hasLength(2));
    final firstRed = changes.indexOf(BrakeAlertPhase.brakeNow);
    expect(changes[firstRed - 1], BrakeAlertPhase.approaching);
  });

  test('calibration suggests warning earlier after repeated late braking', () {
    final suggestions = calibrationSuggestions({
      0: [12, 11, 2, 14, 13],
      1: [1, -2, 3],
    });
    expect(suggestions, hasLength(1));
    expect(suggestions.single.cornerIndex, 0);
    expect(suggestions.single.suggestedOffsetChangeMetres, -10);
  });

  test('BrakeProfile JSON round-trip', () {
    const profile = BrakeProfile(
      id: 'p',
      name: 'Bira – Civic – Dry',
      trackId: 't',
      vehicleType: VehicleType.car,
      pathLatLng: [(14.1, 100.1), (14.2, 100.2)],
      corners: [
        CornerBrakePoint(
          brakeDistanceMetres: 120,
          latitude: 14.1,
          longitude: 100.1,
          offsetMetres: -5,
          locked: true,
        ),
      ],
    );
    final back = BrakeProfile.tryFromJson(profile.toJson());
    expect(back?.corners.single.offsetMetres, -5);
    expect(back?.corners.single.locked, isTrue);
    expect(back?.pathLatLng, hasLength(2));
  });
}
