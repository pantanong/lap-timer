import 'package:clock/clock.dart';
import 'package:lap_timer/features/gps/domain/gps_fix.dart';

/// Turns pre-recorded or generated fixes into a live-looking stream: each
/// fix is emitted when its time comes, and timestamps are shifted so the
/// first fix happens "now". This lets the Simulator and Replay sources drive
/// the real timing pipeline exactly as a GPS receiver would.
///
/// [playbackSpeed] > 1 plays faster than real time (useful for testing).
Stream<GpsFix> pacedFixStream(
  Iterable<GpsFix> fixes, {
  Clock clock = const Clock(),
  double playbackSpeed = 1,
}) async* {
  int? firstFixMicros;
  late int startWallMicros;
  for (final fix in fixes) {
    if (firstFixMicros == null) {
      firstFixMicros = fix.timestampMicros;
      startWallMicros = clock.now().toUtc().microsecondsSinceEpoch;
    }
    final offsetMicros =
        ((fix.timestampMicros - firstFixMicros) / playbackSpeed).round();
    final dueMicros = startWallMicros + offsetMicros;
    final waitMicros = dueMicros - clock.now().toUtc().microsecondsSinceEpoch;
    if (waitMicros > 0) {
      await Future<void>.delayed(Duration(microseconds: waitMicros));
    }
    yield GpsFix(
      timestampMicros: dueMicros,
      latitude: fix.latitude,
      longitude: fix.longitude,
      speedMetresPerSecond: fix.speedMetresPerSecond,
      headingDegrees: fix.headingDegrees,
      horizontalAccuracyMetres: fix.horizontalAccuracyMetres,
    );
  }
}
