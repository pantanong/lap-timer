import 'dart:math' as math;

import 'package:lap_timer/core/geo/local_point.dart';
import 'package:meta/meta.dart';

/// A timing line across the track: start/finish, a sector split, pit entry
/// or pit exit.
///
/// It is stored as a centre point plus the direction of travel. The line
/// itself runs perpendicular to that direction and is [widthMetres] wide.
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
    this.widthMetres = 24,
  });

  /// Decodes [toJson] output; returns null when fields are missing.
  static GateLine? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final lat = json['lat'];
    final lon = json['lon'];
    final bearing = json['bearing'];
    final width = json['width'];
    if (lat is! num || lon is! num) return null;
    return GateLine(
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      travelBearingDegrees: bearing is num ? bearing.toDouble() : null,
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

  /// Total length of the line in metres (half on each side of the centre).
  final double widthMetres;

  /// Returns the same line with a known direction of travel.
  GateLine withBearing(double bearingDegrees) => GateLine(
    latitude: latitude,
    longitude: longitude,
    travelBearingDegrees: bearingDegrees,
    widthMetres: widthMetres,
  );

  /// JSON for storage.
  Map<String, Object?> toJson() => {
    'lat': latitude,
    'lon': longitude,
    if (travelBearingDegrees != null) 'bearing': travelBearingDegrees,
    'width': widthMetres,
  };

  @override
  bool operator ==(Object other) =>
      other is GateLine &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.travelBearingDegrees == travelBearingDegrees &&
      other.widthMetres == widthMetres;

  @override
  int get hashCode =>
      Object.hash(latitude, longitude, travelBearingDegrees, widthMetres);
}

/// A [GateLine] projected onto a local metric plane, ready for fast
/// crossing tests.
class ProjectedGate {
  /// Projects [gate] with [projection].
  factory ProjectedGate(GateLine gate, LocalProjection projection) {
    final centre = projection.toLocal(gate.latitude, gate.longitude);
    final bearing = gate.travelBearingDegrees;
    final direction = bearing == null ? null : _unitFromBearing(bearing);
    return ProjectedGate._(gate, centre, direction);
  }

  ProjectedGate._(this.gate, this.centre, this.travelDirection);

  /// The original gate.
  final GateLine gate;

  /// Centre in local metres.
  final LocalPoint centre;

  /// Unit vector of the direction of travel, if known.
  final LocalPoint? travelDirection;

  static LocalPoint _unitFromBearing(double bearingDegrees) {
    final r = bearingDegrees * math.pi / 180;
    return LocalPoint(math.sin(r), math.cos(r));
  }

  /// If the straight segment [from]→[to] crosses this gate in the right
  /// direction, returns how far along the segment the crossing happens
  /// (0 = at [from], 1 = at [to]); otherwise null.
  ///
  /// When the gate has no direction yet, the segment's own direction is
  /// accepted (the caller then stores it with [GateLine.withBearing]).
  double? crossingFraction(LocalPoint from, LocalPoint to) {
    final move = to - from;
    final moveLength = move.length;
    if (moveLength < 1e-6) return null;
    // Without a stored direction, the line is perpendicular to this move.
    final direction = travelDirection ?? move * (1 / moveLength);
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
}
