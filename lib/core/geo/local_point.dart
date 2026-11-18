import 'dart:math' as math;

import 'package:meta/meta.dart';

/// A position in metres on a flat local plane (x = east, y = north).
///
/// Race tracks are small (a few km), so projecting latitude/longitude onto
/// a flat plane around a nearby origin is accurate to millimetres and makes
/// line-crossing math simple and fast.
@immutable
class LocalPoint {
  /// Creates a point [x] metres east and [y] metres north of the origin.
  const LocalPoint(this.x, this.y);

  /// Metres east of the projection origin.
  final double x;

  /// Metres north of the projection origin.
  final double y;

  /// Vector from [other] to this point.
  LocalPoint operator -(LocalPoint other) =>
      LocalPoint(x - other.x, y - other.y);

  /// Vector sum.
  LocalPoint operator +(LocalPoint other) =>
      LocalPoint(x + other.x, y + other.y);

  /// Scales the vector by [factor].
  LocalPoint operator *(double factor) => LocalPoint(x * factor, y * factor);

  /// 2D cross product (z component); its sign tells which side of a line
  /// a point lies on.
  double cross(LocalPoint other) => x * other.y - y * other.x;

  /// Dot product.
  double dot(LocalPoint other) => x * other.x + y * other.y;

  /// Vector length in metres.
  double get length => math.sqrt(x * x + y * y);

  /// Distance in metres to [other].
  double distanceTo(LocalPoint other) => (this - other).length;

  @override
  bool operator ==(Object other) =>
      other is LocalPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() =>
      'LocalPoint(${x.toStringAsFixed(2)}, '
      '${y.toStringAsFixed(2)})';
}

/// Converts latitude/longitude to [LocalPoint]s around a fixed origin using
/// an equirectangular projection (error < 1 mm per km at track scale).
class LocalProjection {
  /// Creates a projection centred on [originLatitude], [originLongitude].
  LocalProjection({required this.originLatitude, required this.originLongitude})
    : _metresPerDegreeLongitude =
          _metresPerDegreeLatitude * math.cos(originLatitude * math.pi / 180);

  /// Mean metres per degree of latitude.
  static const double _metresPerDegreeLatitude = 111320;

  final double _metresPerDegreeLongitude;

  /// Latitude of the origin, in degrees.
  final double originLatitude;

  /// Longitude of the origin, in degrees.
  final double originLongitude;

  /// Projects a WGS84 coordinate (degrees) to local metres.
  LocalPoint toLocal(double latitude, double longitude) => LocalPoint(
    (longitude - originLongitude) * _metresPerDegreeLongitude,
    (latitude - originLatitude) * _metresPerDegreeLatitude,
  );

  /// Inverse of [toLocal]: returns `(latitude, longitude)` in degrees.
  (double, double) toLatLng(LocalPoint point) => (
    originLatitude + point.y / _metresPerDegreeLatitude,
    originLongitude + point.x / _metresPerDegreeLongitude,
  );
}
