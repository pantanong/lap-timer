import 'package:geolocator/geolocator.dart';
import 'package:lap_timer/core/result.dart';
import 'package:lap_timer/features/gps/data/gps_source.dart';
import 'package:lap_timer/features/gps/domain/gps_fix.dart';

/// The phone's built-in GNSS receiver (usually ~1 Hz, some phones more).
///
/// Wraps `geolocator`; it is the only file in the app that imports it.
class PhoneGpsSource implements GpsSource {
  /// Creates the phone GPS source.
  const PhoneGpsSource();

  @override
  String get displayName => 'Phone GPS';

  @override
  Future<Result<void, GpsFailure>> prepare() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const Err(GpsFailure(GpsFailureKind.serviceDisabled));
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse => const Ok(null),
      LocationPermission.deniedForever => const Err(
        GpsFailure(GpsFailureKind.permissionDeniedForever),
      ),
      LocationPermission.denied || LocationPermission.unableToDetermine =>
        const Err(GpsFailure(GpsFailureKind.permissionDenied)),
    };
  }

  @override
  Stream<GpsFix> fixes() {
    // distanceFilter 0 + shortest interval: we want every fix the chip
    // produces, because lap timing interpolates between consecutive fixes.
    final settings = AndroidSettings(
      intervalDuration: const Duration(milliseconds: 100),
    );
    return Geolocator.getPositionStream(locationSettings: settings).map(_toFix);
  }

  static GpsFix _toFix(Position p) => GpsFix(
    timestampMicros: p.timestamp.toUtc().microsecondsSinceEpoch,
    latitude: p.latitude,
    longitude: p.longitude,
    // Some phones report -1 when speed is unknown; clamp to 0.
    speedMetresPerSecond: p.speed < 0 ? 0 : p.speed,
    headingDegrees: p.heading < 0 ? null : p.heading,
    horizontalAccuracyMetres: p.accuracy,
  );
}
