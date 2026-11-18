import 'package:lap_timer/core/geo/local_point.dart';
import 'package:meta/meta.dart';

/// One GPS sample of a lap, prepared for brake analysis.
@immutable
class TraceSample {
  /// Creates a sample.
  const TraceSample({
    required this.timeMicros,
    required this.distanceMetres,
    required this.speedMetresPerSecond,
    required this.point,
  });

  /// GPS time.
  final int timeMicros;

  /// Distance from the start/finish line along the lap.
  final double distanceMetres;

  /// Ground speed.
  final double speedMetresPerSecond;

  /// Position on the local plane (for re-projection onto a reference path).
  final LocalPoint point;
}

/// All samples of one lap, in time order, with helpers to read the speed
/// and the time at any distance (linear interpolation between samples).
class LapTrace {
  /// Wraps [samples] (must be in time order).
  LapTrace(this.samples);

  /// The samples.
  final List<TraceSample> samples;

  /// Whether there is enough data to analyse.
  bool get isUsable => samples.length >= 3;

  /// Interpolated speed (m/s) at [distance], or null outside the lap.
  double? speedAt(double distance) =>
      _interpolate(distance, (s) => s.speedMetresPerSecond);

  /// Interpolated time (µs) at which the car passed [distance].
  double? timeAt(double distance) =>
      _interpolate(distance, (s) => s.timeMicros.toDouble());

  /// Time (µs) to drive from [fromDistance] to [toDistance].
  int? traversalMicros(double fromDistance, double toDistance) {
    final a = timeAt(fromDistance);
    final b = timeAt(toDistance);
    if (a == null || b == null) return null;
    return (b - a).round();
  }

  double? _interpolate(double distance, double Function(TraceSample) value) {
    if (samples.length < 2) return null;
    for (var i = 1; i < samples.length; i++) {
      final a = samples[i - 1];
      final b = samples[i];
      if (distance >= a.distanceMetres && distance <= b.distanceMetres) {
        final span = b.distanceMetres - a.distanceMetres;
        if (span <= 0) return value(b);
        final f = (distance - a.distanceMetres) / span;
        return value(a) + (value(b) - value(a)) * f;
      }
    }
    return null;
  }
}
