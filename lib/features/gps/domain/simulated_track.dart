import 'dart:math' as math;

import 'package:lap_timer/core/geo/local_point.dart';
import 'package:lap_timer/features/gps/domain/gps_fix.dart';

/// A synthetic circuit and a physically plausible car driving it, used for
/// the Simulator source and for tests. Everything is deterministic: the same
/// inputs always produce exactly the same fixes.
///
/// Shape: a "stadium" — two straights joined by two half circles, with the
/// start/finish in the middle of the bottom straight, driven anticlockwise.
class SimulatedTrack {
  /// Builds the track and pre-computes the speed the car can reach at every
  /// metre.
  SimulatedTrack({
    this.straightLengthMetres = 400,
    this.cornerRadiusMetres = 60,
    this.topSpeedKmh = 160,
    this.cornerSpeedKmh = 75,
    this.brakingG = 0.9,
    this.accelerationG = 0.35,
    this.originLatitude = 14.9583,
    this.originLongitude = 103.0848,
  }) {
    _speedProfile = _buildSpeedProfile();
  }

  /// Length of each straight in metres.
  final double straightLengthMetres;

  /// Radius of each half-circle corner in metres.
  final double cornerRadiusMetres;

  /// Maximum speed on the straights.
  final double topSpeedKmh;

  /// Constant speed through the corners.
  final double cornerSpeedKmh;

  /// Braking deceleration in g used before each corner.
  final double brakingG;

  /// Acceleration in g used out of each corner.
  final double accelerationG;

  /// Latitude the local plane is anchored to (any open area works).
  final double originLatitude;

  /// Longitude the local plane is anchored to.
  final double originLongitude;

  static const double _g = 9.80665;
  static const double _stepMetres = 1;

  late final List<double> _speedProfile;

  /// Total lap length in metres.
  double get lapLengthMetres =>
      2 * straightLengthMetres + 2 * math.pi * cornerRadiusMetres;

  /// Projection used to turn local metres into latitude/longitude.
  LocalProjection get projection => LocalProjection(
    originLatitude: originLatitude,
    originLongitude: originLongitude,
  );

  /// Point on the racing line at [distance] metres from the start line.
  LocalPoint pointAt(double distance) {
    final s = distance % lapLengthMetres;
    final half = straightLengthMetres / 2;
    final r = cornerRadiusMetres;
    final arc = math.pi * r;
    // Segment 1: second half of the bottom straight, heading east.
    if (s < half) return LocalPoint(s, 0);
    // Segment 2: right-hand half circle, turning north.
    if (s < half + arc) {
      final a = (s - half) / r - math.pi / 2;
      return LocalPoint(half + r * math.cos(a), r + r * math.sin(a));
    }
    // Segment 3: top straight, heading west.
    if (s < half + arc + straightLengthMetres) {
      return LocalPoint(half - (s - half - arc), 2 * r);
    }
    // Segment 4: left-hand half circle, turning south.
    final s4 = s - half - arc - straightLengthMetres;
    if (s4 < arc) {
      final a = s4 / r + math.pi / 2;
      return LocalPoint(-half + r * math.cos(a), r + r * math.sin(a));
    }
    // Segment 5: first half of the bottom straight, back to the line.
    return LocalPoint(-half + (s4 - arc), 0);
  }

  /// True when [distance] lies inside one of the two corners.
  bool isInCorner(double distance) {
    final s = distance % lapLengthMetres;
    final half = straightLengthMetres / 2;
    final arc = math.pi * cornerRadiusMetres;
    final topEnd = half + arc + straightLengthMetres;
    return (s >= half && s < half + arc) || (s >= topEnd && s < topEnd + arc);
  }

  /// Speed in m/s the car can carry at [distance] metres into the lap.
  double speedAt(double distance) {
    final i = (distance % lapLengthMetres / _stepMetres).floor();
    return _speedProfile[i.clamp(0, _speedProfile.length - 1)];
  }

  /// Distances (metres from the start line) where braking begins for each
  /// corner — the "ground truth" used to test brake detection.
  List<double> get brakePointDistances {
    final points = <double>[];
    for (var i = 1; i < _speedProfile.length; i++) {
      final wasNotBraking =
          i < 2 || _speedProfile[i - 1] >= _speedProfile[i - 2];
      if (_speedProfile[i] < _speedProfile[i - 1] && wasNotBraking) {
        points.add((i - 1) * _stepMetres);
      }
    }
    return points;
  }

  /// Simulates [laps] laps sampled at [rateHz], starting [runUpMetres]
  /// before the start line at time [startMicros] and stopping
  /// [runOutMetres] after the last crossing (so even a 1 Hz receiver gets a
  /// fix beyond the line).
  ///
  /// Pit stops: for every start/finish crossing number in
  /// [pitStopAtCrossings] (1 = the first time the car reaches the line
  /// after starting), the car drives at [pitLaneSpeedKmh] from
  /// [pitWindowMetres] before to [pitWindowMetres] after the line and
  /// stands still on the line for [pitStopSeconds]. The pit lane runs
  /// [pitLaneOffsetMetres] to the right of the racing line, like a real pit
  /// lane beside the main straight.
  Iterable<GpsFix> drive({
    required int laps,
    double rateHz = 10,
    double runUpMetres = 50,
    double runOutMetres = 100,
    int startMicros = 0,
    Set<int> pitStopAtCrossings = const {},
    double pitLaneSpeedKmh = 50,
    double pitWindowMetres = 150,
    double pitStopSeconds = 30,
  }) sync* {
    const rampMetres = 25.0;
    final dt = 1 / rateHz;
    final endDistance = laps * lapLengthMetres + runUpMetres + runOutMetres;
    final stopDistances = {
      for (final k in pitStopAtCrossings) k * lapLengthMetres,
    };
    final stopsDone = <double>{};
    var distance = 0.0;
    var timeSeconds = 0.0;
    var standingUntil = -1.0;
    while (distance <= endDistance) {
      final trackDistance = distance - runUpMetres;
      var speed = speedAt(trackDistance);
      var offset = 0.0;
      for (final stop in stopDistances) {
        final fromStop = (trackDistance - stop).abs();
        if (fromStop <= pitWindowMetres) {
          speed = math.min(speed, pitLaneSpeedKmh / 3.6);
          final ramp = math.min(1, (pitWindowMetres - fromStop) / rampMetres);
          offset = pitLaneOffsetMetres * ramp;
        }
        // Arrived at the stop point: stand still for the stop duration.
        if (!stopsDone.contains(stop) && trackDistance >= stop) {
          stopsDone.add(stop);
          standingUntil = timeSeconds + pitStopSeconds;
        }
      }
      final standing = timeSeconds < standingUntil;
      yield _fixAt(
        trackDistance,
        standing ? 0 : speed,
        startMicros + (timeSeconds * 1e6).round(),
        offsetMetres: offset,
      );
      if (!standing) distance += speed * dt;
      timeSeconds += dt;
    }
  }

  /// Offset of the simulated pit lane, metres to the right of the racing
  /// line.
  static const double pitLaneOffsetMetres = 10;

  /// Point [offsetMetres] to the right of the racing line at [distance].
  LocalPoint pointBeside(double distance, double offsetMetres) {
    final p = pointAt(distance);
    final ahead = pointAt(distance + 1) - p;
    final length = ahead.length;
    if (length == 0 || offsetMetres == 0) return p;
    // Right-hand normal of the driving direction.
    final right = LocalPoint(ahead.y / length, -ahead.x / length);
    return p + right * offsetMetres;
  }

  GpsFix _fixAt(
    double trackDistance,
    double speed,
    int timestampMicros, {
    double offsetMetres = 0,
  }) {
    final p = pointBeside(trackDistance, offsetMetres);
    final ahead = pointAt(trackDistance + 1) - pointAt(trackDistance);
    final heading = (math.atan2(ahead.x, ahead.y) * 180 / math.pi + 360) % 360;
    final (lat, lon) = projection.toLatLng(p);
    return GpsFix(
      timestampMicros: timestampMicros,
      latitude: lat,
      longitude: lon,
      speedMetresPerSecond: speed,
      headingDegrees: heading,
      horizontalAccuracyMetres: 1,
    );
  }

  /// Corner limit, then a backward pass (braking) and a forward pass
  /// (acceleration) — the classic lap-simulation speed envelope.
  List<double> _buildSpeedProfile() {
    final n = (lapLengthMetres / _stepMetres).ceil();
    final top = topSpeedKmh / 3.6;
    final corner = cornerSpeedKmh / 3.6;
    final v = List<double>.generate(
      n,
      (i) => isInCorner(i * _stepMetres) ? corner : top,
    );
    // Two passes around the loop so wrap-around limits propagate.
    for (var pass = 0; pass < 2; pass++) {
      for (var i = n - 1; i >= 0; i--) {
        final next = v[(i + 1) % n];
        final limit = math.sqrt(next * next + 2 * brakingG * _g * _stepMetres);
        if (v[i] > limit) v[i] = limit;
      }
      for (var i = 0; i < n; i++) {
        final prev = v[(i - 1 + n) % n];
        final limit = math.sqrt(
          prev * prev + 2 * accelerationG * _g * _stepMetres,
        );
        if (v[i] > limit) v[i] = limit;
      }
    }
    return v;
  }
}
