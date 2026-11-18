import 'package:lap_timer/features/sessions/domain/session.dart';
import 'package:meta/meta.dart';

/// How brake points are chosen from the learning laps.
enum BrakeLearningMethod {
  /// Method 1: the brake points of the fastest lap.
  fastestLap,

  /// Method 2 (conditional): per corner, the latest brake point of any lap
  /// — but only if that corner was not slower, the minimum and exit speeds
  /// were not lower and the entry speed was similar.
  deepestValid,
}

/// The brake point of one corner.
@immutable
class CornerBrakePoint {
  /// Creates a corner.
  const CornerBrakePoint({
    required this.brakeDistanceMetres,
    required this.latitude,
    required this.longitude,
    this.offsetMetres = 0,
    this.locked = false,
    this.sourceLapNumber,
  });

  /// Decodes [toJson] output; returns null when malformed.
  static CornerBrakePoint? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final d = json['d'];
    final lat = json['lat'];
    final lon = json['lon'];
    if (d is! num || lat is! num || lon is! num) return null;
    final offset = json['offset'];
    final lap = json['lap'];
    return CornerBrakePoint(
      brakeDistanceMetres: d.toDouble(),
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      offsetMetres: offset is num ? offset.toDouble() : 0,
      locked: json['locked'] == true,
      sourceLapNumber: lap is int ? lap : null,
    );
  }

  /// Learned brake point, metres along the reference path.
  final double brakeDistanceMetres;

  /// Brake point latitude (for the map).
  final double latitude;

  /// Brake point longitude (for the map).
  final double longitude;

  /// User adjustment of the *alert* for this corner: negative = warn
  /// earlier, positive = warn later. The learned point is unchanged.
  final double offsetMetres;

  /// Locked corners are never changed by learning.
  final bool locked;

  /// Lap the brake point came from.
  final int? sourceLapNumber;

  /// Returns a copy with the given fields replaced.
  CornerBrakePoint copyWith({double? offsetMetres, bool? locked}) =>
      CornerBrakePoint(
        brakeDistanceMetres: brakeDistanceMetres,
        latitude: latitude,
        longitude: longitude,
        offsetMetres: offsetMetres ?? this.offsetMetres,
        locked: locked ?? this.locked,
        sourceLapNumber: sourceLapNumber,
      );

  /// JSON for storage.
  Map<String, Object?> toJson() => {
    'd': brakeDistanceMetres,
    'lat': latitude,
    'lon': longitude,
    'offset': offsetMetres,
    'locked': locked,
    'lap': ?sourceLapNumber,
  };
}

/// A saved set of brake points for one track and vehicle, e.g.
/// "Buriram – Civic – Dry – v2", with the reference path they are
/// measured along.
@immutable
class BrakeProfile {
  /// Creates a profile.
  const BrakeProfile({
    required this.id,
    required this.name,
    required this.trackId,
    required this.vehicleType,
    required this.pathLatLng,
    required this.corners,
  });

  /// Decodes [toJson] output; returns null when malformed.
  static BrakeProfile? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final id = json['id'];
    final name = json['name'];
    final trackId = json['trackId'];
    final vehicle = json['vehicle'];
    final path = json['path'];
    final corners = json['corners'];
    if (id is! String ||
        name is! String ||
        trackId is! String ||
        vehicle is! String ||
        path is! List<Object?> ||
        corners is! List<Object?>) {
      return null;
    }
    final pathLatLng = <(double, double)>[];
    for (final p in path) {
      if (p is List<Object?> && p.length == 2) {
        final [lat, lon] = p;
        if (lat is num && lon is num) {
          pathLatLng.add((lat.toDouble(), lon.toDouble()));
        }
      }
    }
    return BrakeProfile(
      id: id,
      name: name,
      trackId: trackId,
      vehicleType: VehicleType.values.asNameMap()[vehicle] ?? VehicleType.car,
      pathLatLng: pathLatLng,
      corners: [for (final c in corners) ?CornerBrakePoint.tryFromJson(c)],
    );
  }

  /// Stable identifier.
  final String id;

  /// User-visible name.
  final String name;

  /// Track the profile belongs to.
  final String trackId;

  /// Vehicle kind the profile belongs to.
  final VehicleType vehicleType;

  /// Reference path as (latitude, longitude), start/finish first.
  final List<(double, double)> pathLatLng;

  /// Corners in driving order.
  final List<CornerBrakePoint> corners;

  /// Returns a copy with the given fields replaced.
  BrakeProfile copyWith({
    String? id,
    String? name,
    List<CornerBrakePoint>? corners,
  }) => BrakeProfile(
    id: id ?? this.id,
    name: name ?? this.name,
    trackId: trackId,
    vehicleType: vehicleType,
    pathLatLng: pathLatLng,
    corners: corners ?? this.corners,
  );

  /// JSON for storage.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'trackId': trackId,
    'vehicle': vehicleType.name,
    'path': [
      for (final (lat, lon) in pathLatLng) [lat, lon],
    ],
    'corners': [for (final c in corners) c.toJson()],
  };
}
