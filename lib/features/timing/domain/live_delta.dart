import 'package:lap_timer/core/geo/local_point.dart';
import 'package:meta/meta.dart';

/// One sample of a lap for the live delta: where the car was and how long
/// after the start of the lap.
@immutable
class _DeltaSample {
  const _DeltaSample(this.point, this.elapsedMicros);

  final LocalPoint point;
  final int elapsedMicros;
}

/// Live gap to the best lap, updated with every GPS fix.
///
/// The best racing lap is kept as a reference line with the time at each
/// point. For the current position, the closest point on that line gives
/// how long the best lap took to get *here*; the live delta is the
/// current lap's elapsed time minus that (negative = ahead / faster).
///
/// Projecting onto the reference line (instead of comparing travelled
/// distance) keeps the delta accurate even when the driven line differs a
/// little from lap to lap.
class LiveDeltaTracker {
  /// Creates a tracker; [projection] is the session's local plane.
  LiveDeltaTracker(this.projection);

  /// Local plane of the session.
  final LocalProjection projection;

  /// Beyond this distance from the reference line there is no delta (e.g.
  /// pit lane, or a different route).
  static const double maximumOffPathMetres = 30;

  /// The search follows the car along the reference line within this
  /// window, so a nearby part of the track is never picked by mistake.
  static const int _searchWindow = 60;

  List<_DeltaSample> _current = [];
  int? _currentLapStartMicros;
  List<_DeltaSample>? _reference;
  int? _referenceLapMicros;
  int _referenceIndex = 0;

  /// Time of the reference (best) lap, if any.
  int? get referenceLapMicros => _referenceLapMicros;

  /// Start/finish crossed at [atMicros]: a new lap begins.
  void startLap(int atMicros) {
    _current = [];
    _currentLapStartMicros = atMicros;
    _referenceIndex = 0;
  }

  /// The lap that just ended. A faster racing lap becomes the reference.
  void completeLap({required int lapMicros, required bool isRacingLap}) {
    if (!isRacingLap || _current.length < 10) return;
    final best = _referenceLapMicros;
    if (best == null || lapMicros < best) {
      _reference = List.unmodifiable(_current);
      _referenceLapMicros = lapMicros;
    }
  }

  /// Adds a fix and returns the live delta in microseconds, or null when
  /// there is no reference yet, no lap in progress, or the car is off the
  /// reference line.
  int? add({
    required double latitude,
    required double longitude,
    required int timeMicros,
  }) {
    final start = _currentLapStartMicros;
    if (start == null) return null;
    final point = projection.toLocal(latitude, longitude);
    final elapsed = timeMicros - start;
    _current.add(_DeltaSample(point, elapsed));
    final reference = _reference;
    if (reference == null || reference.length < 2) return null;
    final referenceElapsed = _referenceTimeAt(reference, point);
    if (referenceElapsed == null) return null;
    return elapsed - referenceElapsed;
  }

  /// Time the reference lap reached the point closest to [p], interpolated
  /// along the reference segment, or null when too far from the line.
  int? _referenceTimeAt(List<_DeltaSample> reference, LocalPoint p) {
    final from = (_referenceIndex - 5).clamp(0, reference.length - 2);
    final to = (_referenceIndex + _searchWindow).clamp(0, reference.length - 1);
    var bestDistance = double.infinity;
    var bestTime = 0.0;
    var bestIndex = _referenceIndex;
    for (var i = from; i < to; i++) {
      final a = reference[i];
      final b = reference[i + 1];
      final ab = b.point - a.point;
      final len2 = ab.dot(ab);
      final t = len2 == 0
          ? 0.0
          : ((p - a.point).dot(ab) / len2).clamp(0.0, 1.0);
      final d = (a.point + ab * t).distanceTo(p);
      if (d < bestDistance) {
        bestDistance = d;
        bestTime = a.elapsedMicros + (b.elapsedMicros - a.elapsedMicros) * t;
        bestIndex = i;
      }
    }
    if (bestDistance > maximumOffPathMetres) return null;
    _referenceIndex = bestIndex;
    return bestTime.round();
  }
}
