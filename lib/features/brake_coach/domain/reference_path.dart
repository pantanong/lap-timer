import 'package:lap_timer/core/geo/local_point.dart';
import 'package:lap_timer/features/brake_coach/domain/lap_trace.dart';

/// The line driven on the reference lap, used to measure "how far along
/// the lap" the car is in a way that is the same on every lap.
///
/// Plain odometer distance drifts a few metres per lap (different lines,
/// GPS noise); projecting the car onto one fixed path does not.
class ReferencePath {
  /// Creates a path from points in driving order (first = start/finish).
  ReferencePath(List<LocalPoint> points) : points = List.unmodifiable(points) {
    var total = 0.0;
    _cumulative.add(0);
    for (var i = 1; i < this.points.length; i++) {
      total += this.points[i].distanceTo(this.points[i - 1]);
      _cumulative.add(total);
    }
  }

  /// Builds the path from a lap, keeping a point every [spacingMetres].
  factory ReferencePath.fromTrace(LapTrace trace, {double spacingMetres = 2}) {
    final pts = <LocalPoint>[];
    for (final s in trace.samples) {
      if (pts.isEmpty || pts.last.distanceTo(s.point) >= spacingMetres) {
        pts.add(s.point);
      }
    }
    return ReferencePath(pts);
  }

  /// Path points (local metres).
  final List<LocalPoint> points;
  final List<double> _cumulative = [];

  /// Length of the path.
  double get lengthMetres => _cumulative.isEmpty ? 0 : _cumulative.last;

  /// Point at [distance] along the path.
  LocalPoint pointAt(double distance) {
    if (points.isEmpty) return LocalPoint.zero;
    for (var i = 1; i < points.length; i++) {
      if (_cumulative[i] >= distance) {
        final span = _cumulative[i] - _cumulative[i - 1];
        final f = span == 0 ? 0.0 : (distance - _cumulative[i - 1]) / span;
        return points[i - 1] + (points[i] - points[i - 1]) * f;
      }
    }
    return points.last;
  }

  /// Distance along the path of the point closest to [p], searching only
  /// within ±[windowMetres] of [nearDistance] when given (prevents jumping
  /// to another part of the track that passes nearby). Returns
  /// `(distance, offPathMetres)` or null for an empty path.
  (double, double)? locate(
    LocalPoint p, {
    double? nearDistance,
    double windowMetres = 80,
  }) {
    if (points.length < 2) return null;
    var bestDistance = 0.0;
    var bestOffset = double.infinity;
    for (var i = 1; i < points.length; i++) {
      final near = nearDistance;
      if (near != null &&
          (_cumulative[i] < near - windowMetres ||
              _cumulative[i - 1] > near + windowMetres)) {
        continue;
      }
      final a = points[i - 1];
      final ab = points[i] - a;
      final len2 = ab.dot(ab);
      final t = len2 == 0 ? 0.0 : ((p - a).dot(ab) / len2).clamp(0.0, 1.0);
      final closest = a + ab * t;
      final offset = closest.distanceTo(p);
      if (offset < bestOffset) {
        bestOffset = offset;
        bestDistance =
            _cumulative[i - 1] + t * (_cumulative[i] - _cumulative[i - 1]);
      }
    }
    if (bestOffset == double.infinity) return null;
    return (bestDistance, bestOffset);
  }
}
