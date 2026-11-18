import 'package:meta/meta.dart';

/// One position sample from any GPS source (phone, external receiver,
/// simulator or a replayed log).
///
/// Time is stored as microseconds since the Unix epoch (UTC) so that
/// 10–25 Hz receivers keep full precision and logs round-trip exactly.
@immutable
class GpsFix {
  /// Creates a fix. Speeds are in metres per second, angles in degrees.
  const GpsFix({
    required this.timestampMicros,
    required this.latitude,
    required this.longitude,
    required this.speedMetresPerSecond,
    this.headingDegrees,
    this.horizontalAccuracyMetres,
  });

  /// Decodes a fix written by [toJson]. Returns `null` for malformed input
  /// instead of throwing, so one bad line never breaks a whole log.
  static GpsFix? tryFromJson(Map<String, Object?> json) {
    final t = json['t'];
    final lat = json['lat'];
    final lon = json['lon'];
    final speed = json['v'];
    if (t is! int || lat is! num || lon is! num || speed is! num) {
      return null;
    }
    final heading = json['hdg'];
    final accuracy = json['acc'];
    return GpsFix(
      timestampMicros: t,
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      speedMetresPerSecond: speed.toDouble(),
      headingDegrees: heading is num ? heading.toDouble() : null,
      horizontalAccuracyMetres: accuracy is num ? accuracy.toDouble() : null,
    );
  }

  /// Sample time, microseconds since the Unix epoch (UTC).
  final int timestampMicros;

  /// WGS84 latitude in degrees.
  final double latitude;

  /// WGS84 longitude in degrees.
  final double longitude;

  /// Ground speed reported by the receiver (Doppler), metres per second.
  final double speedMetresPerSecond;

  /// Course over ground in degrees (0 = north), if the source provides it.
  final double? headingDegrees;

  /// Estimated horizontal error radius in metres, if known.
  final double? horizontalAccuracyMetres;

  /// Ground speed in km/h, for display.
  double get speedKmh => speedMetresPerSecond * 3.6;

  /// Compact JSON used by the raw GPS log (one object per line).
  Map<String, Object?> toJson() => {
    't': timestampMicros,
    'lat': latitude,
    'lon': longitude,
    'v': speedMetresPerSecond,
    if (headingDegrees != null) 'hdg': headingDegrees,
    if (horizontalAccuracyMetres != null) 'acc': horizontalAccuracyMetres,
  };

  @override
  bool operator ==(Object other) =>
      other is GpsFix &&
      other.timestampMicros == timestampMicros &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.speedMetresPerSecond == speedMetresPerSecond &&
      other.headingDegrees == headingDegrees &&
      other.horizontalAccuracyMetres == horizontalAccuracyMetres;

  @override
  int get hashCode => Object.hash(
    timestampMicros,
    latitude,
    longitude,
    speedMetresPerSecond,
    headingDegrees,
    horizontalAccuracyMetres,
  );
}
