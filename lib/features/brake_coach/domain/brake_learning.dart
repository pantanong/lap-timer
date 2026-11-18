import 'package:lap_timer/core/geo/local_point.dart';
import 'package:lap_timer/features/brake_coach/domain/brake_detection.dart';
import 'package:lap_timer/features/brake_coach/domain/brake_profile.dart';
import 'package:lap_timer/features/brake_coach/domain/lap_trace.dart';
import 'package:lap_timer/features/brake_coach/domain/reference_path.dart';
import 'package:meta/meta.dart';

/// A completed racing lap available for learning.
@immutable
class LearningLap {
  /// Creates a learning lap.
  const LearningLap({
    required this.lapNumber,
    required this.lapTimeMicros,
    required this.trace,
  });

  /// Lap number in the session.
  final int lapNumber;

  /// Lap time.
  final int lapTimeMicros;

  /// GPS samples of the lap.
  final LapTrace trace;
}

/// Result of learning: the reference path and one brake point per corner.
@immutable
class LearnedBrakePoints {
  /// Creates the result.
  const LearnedBrakePoints({required this.path, required this.corners});

  /// Path of the fastest lap; all distances are measured along it.
  final ReferencePath path;

  /// Corners in driving order.
  final List<CornerBrakePoint> corners;
}

/// Brake events of one lap, re-measured along the reference path.
class _LapCandidates {
  _LapCandidates(this.lap, this.events, this.pathDistances);
  final LearningLap lap;
  final List<BrakeEvent> events;
  final List<double> pathDistances;
}

/// Learns the brake point of every corner from [laps].
///
/// - The fastest lap defines the reference path and the corners.
/// - [BrakeLearningMethod.fastestLap] keeps its brake points.
/// - [BrakeLearningMethod.deepestValid] moves a corner's point later only
///   when another lap braked later *and* was not slower through that
///   corner, kept at least the same minimum and exit speed, and entered at
///   a similar speed. It never moves more than [maximumShiftMetres] (GPS
///   glitch guard). Because it is recomputed from all laps each time, a
///   point can also move back earlier.
/// - [locked] corners (from a saved profile) are kept as they are.
LearnedBrakePoints? learnBrakePoints({
  required List<LearningLap> laps,
  required BrakeDetectionSettings detection,
  required BrakeLearningMethod method,
  required LocalProjection projection,
  List<CornerBrakePoint> locked = const [],
  double clusterRadiusMetres = 40,
  double maximumShiftMetres = 30,
}) {
  final usable = laps.where((l) => l.trace.isUsable).toList();
  if (usable.isEmpty) return null;
  usable.sort((a, b) => a.lapTimeMicros.compareTo(b.lapTimeMicros));
  final fastest = usable.first;
  final path = ReferencePath.fromTrace(fastest.trace);

  final candidates = [
    for (final lap in usable) _relocate(lap, path, detection),
  ];
  final base = candidates.first; // the fastest lap
  final corners = <CornerBrakePoint>[];
  for (var c = 0; c < base.events.length; c++) {
    var bestDistance = base.pathDistances[c];
    var bestLap = fastest.lapNumber;
    if (method == BrakeLearningMethod.deepestValid) {
      // Every lap is judged over the same stretch of track: from 30 m
      // before the reference brake point to 80 m after the reference
      // lap's slowest point.
      final baseEvent = base.events[c];
      final window = (
        from: base.pathDistances[c] - 30,
        to:
            base.pathDistances[c] +
            baseEvent.minSpeedDistanceMetres -
            baseEvent.onsetDistanceMetres +
            80,
      );
      final baseline = _CornerStats.of(base, c, window);
      for (final other in candidates.skip(1)) {
        final match = _nearestEvent(
          other,
          base.pathDistances[c],
          clusterRadiusMetres,
        );
        if (match == null) continue;
        final d = other.pathDistances[match];
        if (d <= bestDistance) continue;
        if (d - base.pathDistances[c] > maximumShiftMetres) continue;
        final stats = _CornerStats.of(other, match, window);
        if (baseline != null && stats != null && stats.isAsGoodAs(baseline)) {
          bestDistance = d;
          bestLap = other.lap.lapNumber;
        }
      }
    }
    final (lat, lon) = projection.toLatLng(path.pointAt(bestDistance));
    corners.add(
      CornerBrakePoint(
        brakeDistanceMetres: bestDistance,
        latitude: lat,
        longitude: lon,
        sourceLapNumber: bestLap,
      ),
    );
  }
  return LearnedBrakePoints(
    path: path,
    corners: _keepLocked(corners, locked, clusterRadiusMetres),
  );
}

_LapCandidates _relocate(
  LearningLap lap,
  ReferencePath path,
  BrakeDetectionSettings detection,
) {
  final events = detectBrakeEvents(lap.trace, detection);
  final distances = [
    for (final e in events)
      path.locate(e.onsetPoint)?.$1 ?? e.onsetDistanceMetres,
  ];
  return _LapCandidates(lap, events, distances);
}

int? _nearestEvent(_LapCandidates lap, double distance, double radius) {
  int? best;
  var bestGap = radius;
  for (var i = 0; i < lap.pathDistances.length; i++) {
    final gap = (lap.pathDistances[i] - distance).abs();
    if (gap <= bestGap) {
      bestGap = gap;
      best = i;
    }
  }
  return best;
}

/// Replaces learned corners near a locked corner with the locked one.
List<CornerBrakePoint> _keepLocked(
  List<CornerBrakePoint> learned,
  List<CornerBrakePoint> locked,
  double radius,
) {
  if (locked.isEmpty) return learned;
  final result = [
    for (final c in learned)
      if (!locked.any(
        (l) => (l.brakeDistanceMetres - c.brakeDistanceMetres).abs() < radius,
      ))
        c,
    ...locked,
  ]..sort((a, b) => a.brakeDistanceMetres.compareTo(b.brakeDistanceMetres));
  return result;
}

/// How a lap drove one corner: time over a fixed stretch of track (path
/// distances `window.from`–`window.to`), entry, minimum and exit speeds.
class _CornerStats {
  _CornerStats(this.segmentMicros, this.entry, this.minimum, this.exit);

  static _CornerStats? of(
    _LapCandidates lap,
    int index,
    ({double from, double to}) window,
  ) {
    final event = lap.events[index];
    // Shift between this lap's odometer and the reference path.
    final shift = lap.pathDistances[index] - event.onsetDistanceMetres;
    final time = lap.lap.trace.traversalMicros(
      window.from - shift,
      window.to - shift,
    );
    // Exit speed 80 m after this lap's own slowest point: did the later
    // braking compromise the exit?
    final exit = lap.lap.trace.speedAt(event.minSpeedDistanceMetres + 80);
    if (time == null || exit == null) return null;
    return _CornerStats(
      time,
      event.entrySpeedMetresPerSecond,
      event.minSpeedMetresPerSecond,
      exit,
    );
  }

  final int segmentMicros;
  final double entry;
  final double minimum;
  final double exit;

  /// Not slower, minimum and exit speed not lower (0.3 m/s ≈ 1 km/h
  /// tolerance), entry speed within 1.5 m/s (≈ 5 km/h).
  bool isAsGoodAs(_CornerStats base) =>
      segmentMicros <= base.segmentMicros &&
      minimum >= base.minimum - 0.3 &&
      exit >= base.exit - 0.3 &&
      (entry - base.entry).abs() <= 1.5;
}
