import 'dart:math' as math;

import 'package:lap_timer/core/geo/local_point.dart';
import 'package:meta/meta.dart';

/// A timing line across the track: start/finish, a sector split, pit entry
/// or pit exit.
///
/// It is stored as a centre point plus the direction of travel. The line
/// itself runs perpendicular to that direction and is [widthMetres] wide.
/// A line drawn on the map (two taps, one on each edge of the track) only
/// knows its own orientation ([axisBearingDegrees]); the direction of
/// travel is then learned from the first crossing.
/// Keeping the line short and directional means a car on a parallel road
/// (e.g. the pit lane next to the main straight) never triggers it, and
/// driving across it backwards does not count.
@immutable
class GateLine {
  /// Creates a gate centred at [latitude]/[longitude].
  const GateLine({
    required this.latitude,
    required this.longitude,
    this.travelBearingDegrees,
    this.axisBearingDegrees,
    this.widthMetres = 24,
  });

  /// A line between two points tapped on the map, e.g. on each edge of the
  /// track. Adds [marginMetres] on each side so a car on the kerb still
  /// counts.
  factory GateLine.fromEndpoints(
    double latitudeA,
    double longitudeA,
    double latitudeB,
    double longitudeB, {
    double marginMetres = 3,
  }) {
    final midLat = (latitudeA + latitudeB) / 2;
    final midLon = (longitudeA + longitudeB) / 2;
    final projection = LocalProjection(
      originLatitude: midLat,
      originLongitude: midLon,
    );
    final a = projection.toLocal(latitudeA, longitudeA);
    final b = projection.toLocal(latitudeB, longitudeB);
    final axis = b - a;
    final bearing = (math.atan2(axis.x, axis.y) * 180 / math.pi + 360) % 360;
    return GateLine(
      latitude: midLat,
      longitude: midLon,
      axisBearingDegrees: bearing % 180,
      widthMetres: axis.length + 2 * marginMetres,
    );
  }

  /// Decodes [toJson] output; returns null when fields are missing.
  static GateLine? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final lat = json['lat'];
    final lon = json['lon'];
    final bearing = json['bearing'];
    final axis = json['axis'];
    final width = json['width'];
    if (lat is! num || lon is! num) return null;
    return GateLine(
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      travelBearingDegrees: bearing is num ? bearing.toDouble() : null,
      axisBearingDegrees: axis is num ? axis.toDouble() : null,
      widthMetres: width is num ? width.toDouble() : 24,
    );
  }

  /// Centre latitude in degrees.
  final double latitude;

  /// Centre longitude in degrees.
  final double longitude;

  /// Direction of travel across the line (0 = north, 90 = east). Null when
  /// the line was set while standing still: it is then learned from the
  /// first crossing (see [withBearing]).
  final double? travelBearingDegrees;

  /// Orientation of the line itself (0–180°), when known but the direction
  /// of travel is not (line drawn on the map).
  final double? axisBearingDegrees;

  /// Total length of the line in metres (half on each side of the centre).
  final double widthMetres;

  /// Orientation of the drawn line, from whichever information is known;
  /// null when only a point is known (set while standing still).
  double? get lineAxisDegrees {
    final travel = travelBearingDegrees;
    if (travel != null) return (travel + 90) % 180;
    return axisBearingDegrees;
  }

  /// The two ends of the line as `(latitude, longitude)` pairs, for drawing
  /// on a map; null when only a point is known.
  ((double, double), (double, double))? endpoints() {
    final axis = lineAxisDegrees;
    if (axis == null) return null;
    final projection = LocalProjection(
      originLatitude: latitude,
      originLongitude: longitude,
    );
    final r = axis * math.pi / 180;
    final half = LocalPoint(math.sin(r), math.cos(r)) * (widthMetres / 2);
    return (
      projection.toLatLng(LocalPoint.zero - half),
      projection.toLatLng(half),
    );
  }

  /// Returns the same line with a known direction of travel.
  GateLine withBearing(double bearingDegrees) => GateLine(
    latitude: latitude,
    longitude: longitude,
    travelBearingDegrees: bearingDegrees,
    axisBearingDegrees: axisBearingDegrees,
    widthMetres: widthMetres,
  );

  /// JSON for storage.
  Map<String, Object?> toJson() => {
    'lat': latitude,
    'lon': longitude,
    'bearing': ?travelBearingDegrees,
    'axis': ?axisBearingDegrees,
    'width': widthMetres,
  };

  @override
  bool operator ==(Object other) =>
      other is GateLine &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.travelBearingDegrees == travelBearingDegrees &&
      other.axisBearingDegrees == axisBearingDegrees &&
      other.widthMetres == widthMetres;

  @override
  int get hashCode => Object.hash(
    latitude,
    longitude,
    travelBearingDegrees,
    axisBearingDegrees,
    widthMetres,
  );
}

/// A [GateLine] projected onto a local metric plane, ready for fast
/// crossing tests.
class ProjectedGate {
  /// Projects [gate] with [projection].
  factory ProjectedGate(GateLine gate, LocalProjection projection) {
    final centre = projection.toLocal(gate.latitude, gate.longitude);
    final bearing = gate.travelBearingDegrees;
    final direction = bearing == null ? null : _unitFromBearing(bearing);
    final axis = gate.axisBearingDegrees;
    // The normal of a drawn line: perpendicular to its axis. Which of the
    // two normals is "forward" is decided by the first crossing.
    final normal = axis == null ? null : _unitFromBearing(axis + 90);
    return ProjectedGate._(gate, centre, direction, normal);
  }

  ProjectedGate._(this.gate, this.centre, this.travelDirection, this._normal);

  /// The original gate.
  final GateLine gate;

  /// Centre in local metres.
  final LocalPoint centre;

  /// Unit vector of the direction of travel, if known.
  final LocalPoint? travelDirection;

  /// Unit normal of a drawn line whose travel direction is still unknown.
  final LocalPoint? _normal;

  static LocalPoint _unitFromBearing(double bearingDegrees) {
    final r = bearingDegrees * math.pi / 180;
    return LocalPoint(math.sin(r), math.cos(r));
  }

  /// If the straight segment [from]→[to] crosses this gate in the right
  /// direction, returns how far along the segment the crossing happens
  /// (0 = at [from], 1 = at [to]); otherwise null.
  ///
  /// When the gate has no direction yet, either direction is accepted (the
  /// caller then stores it with [GateLine.withBearing]).
  double? crossingFraction(LocalPoint from, LocalPoint to) {
    final move = to - from;
    final moveLength = move.length;
    if (moveLength < 1e-6) return null;
    final direction = _directionFor(move, moveLength);
    if (move.dot(direction) <= 0) return null; // wrong way across

    // Signed distance of each end along the travel direction, measured
    // from the line. A crossing means the sign flips from - to +.
    final before = (from - centre).dot(direction);
    final after = (to - centre).dot(direction);
    if (before > 0 || after < 0 || before == after) return null;
    final fraction = before / (before - after);

    // The crossing point must lie within the line's width.
    final hit = from + move * fraction;
    final lateral = (hit - centre).cross(direction).abs();
    if (lateral > gate.widthMetres / 2) return null;
    return fraction;
  }

  /// The direction a crossing must follow: the stored travel direction; or
  /// for a drawn line, its normal pointing the way this move goes; or, for
  /// a point set while standing, the move itself.
  LocalPoint _directionFor(LocalPoint move, double moveLength) {
    final travel = travelDirection;
    if (travel != null) return travel;
    final normal = _normal;
    if (normal != null) return move.dot(normal) >= 0 ? normal : normal * -1;
    return move * (1 / moveLength);
  }
}
