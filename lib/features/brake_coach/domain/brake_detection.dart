import 'package:lap_timer/core/geo/local_point.dart';
import 'package:lap_timer/features/brake_coach/domain/lap_trace.dart';
import 'package:lap_timer/features/sessions/domain/session.dart';
import 'package:meta/meta.dart';

/// Standard gravity, m/s².
const double gravity = 9.80665;

/// How braking is recognised. Thresholds are in g (deceleration) so they
/// mean the same thing at 1 Hz and at 25 Hz — unlike a fixed "km/h drop
/// between two samples".
@immutable
class BrakeDetectionSettings {
  /// Creates settings.
  const BrakeDetectionSettings({
    this.brakingG = 0.3,
    this.windowMicros = 300000,
    this.minimumSpeedDropMetresPerSecond = 3,
  });

  /// Default thresholds per vehicle (null for bicycles: no brake coach).
  static BrakeDetectionSettings? forVehicle(VehicleType type) => switch (type) {
    VehicleType.car => const BrakeDetectionSettings(),
    VehicleType.motorcycle => const BrakeDetectionSettings(),
    VehicleType.kart => const BrakeDetectionSettings(brakingG: 0.25),
    VehicleType.bicycle => null,
  };

  /// Deceleration that counts as braking (lifting off the throttle is
  /// typically 0.1–0.2 g, so it is not mistaken for braking).
  final double brakingG;

  /// Window over which deceleration is measured.
  final int windowMicros;

  /// A braking zone must lose at least this much speed (≈ 11 km/h).
  final double minimumSpeedDropMetresPerSecond;
}

/// One braking zone found in a lap.
@immutable
class BrakeEvent {
  /// Creates an event.
  const BrakeEvent({
    required this.onsetDistanceMetres,
    required this.onsetPoint,
    required this.entrySpeedMetresPerSecond,
    required this.minSpeedMetresPerSecond,
    required this.minSpeedDistanceMetres,
  });

  /// Where the speed started to fall (the brake point).
  final double onsetDistanceMetres;

  /// Position of the brake point.
  final LocalPoint onsetPoint;

  /// Speed at the brake point.
  final double entrySpeedMetresPerSecond;

  /// Lowest speed in the corner.
  final double minSpeedMetresPerSecond;

  /// Where the lowest speed happened.
  final double minSpeedDistanceMetres;
}

/// Finds every braking zone in [trace].
///
/// 1. Deceleration is measured over a short window (default 0.3 s).
/// 2. When it exceeds the braking threshold, we walk back to the sample
///    where the speed *started* falling — that is the brake point, not the
///    (later) moment the threshold was crossed.
/// 3. The zone ends where the speed starts rising again (the minimum).
/// 4. Zones losing less than ~11 km/h are ignored (small lifts, noise).
List<BrakeEvent> detectBrakeEvents(
  LapTrace trace,
  BrakeDetectionSettings settings,
) {
  final s = trace.samples;
  final events = <BrakeEvent>[];
  var i = 1;
  while (i < s.length) {
    if (_decelerationG(s, i, settings.windowMicros) < settings.brakingG) {
      i++;
      continue;
    }
    // Walk back to where the speed began to fall: keep going back while
    // the previous sample was faster (we are still inside the decline).
    var onset = i;
    while (onset > 0 &&
        s[onset - 1].speedMetresPerSecond >
            s[onset].speedMetresPerSecond + 0.02) {
      onset--;
    }
    // Walk forward to the minimum speed.
    var min = i;
    while (min + 1 < s.length &&
        s[min + 1].speedMetresPerSecond <= s[min].speedMetresPerSecond + 0.1) {
      min++;
    }
    final drop = s[onset].speedMetresPerSecond - s[min].speedMetresPerSecond;
    if (drop >= settings.minimumSpeedDropMetresPerSecond) {
      final refined = _refineOnset(s, onset);
      events.add(
        BrakeEvent(
          onsetDistanceMetres: refined.distanceMetres,
          onsetPoint: refined.point,
          entrySpeedMetresPerSecond: s[onset].speedMetresPerSecond,
          minSpeedMetresPerSecond: s[min].speedMetresPerSecond,
          minSpeedDistanceMetres: s[min].distanceMetres,
        ),
      );
    }
    i = min + 1;
  }
  return events;
}

/// The brake point lies somewhere between the last fast sample [onset]
/// and the next one. At low GPS rates (1 Hz ≈ 40 m apart) that matters, so
/// the point is estimated from the deceleration measured just after it:
/// braking at a constant rate from the cruising speed, where must it have
/// started to reach the speed of the next sample?
({double distanceMetres, LocalPoint point}) _refineOnset(
  List<TraceSample> s,
  int onset,
) {
  final o = s[onset];
  if (onset + 2 >= s.length) {
    return (distanceMetres: o.distanceMetres, point: o.point);
  }
  final a = s[onset + 1];
  final b = s[onset + 2];
  final span = b.distanceMetres - a.distanceMetres;
  final v0 = o.speedMetresPerSecond;
  final v1 = a.speedMetresPerSecond;
  final v2 = b.speedMetresPerSecond;
  // Deceleration (m/s²) between the two samples after the onset.
  final decel = span <= 0 ? 0.0 : (v1 * v1 - v2 * v2) / (2 * span);
  if (decel <= 0 || v0 <= v1) {
    return (distanceMetres: o.distanceMetres, point: o.point);
  }
  final brakingDistance = (v0 * v0 - v1 * v1) / (2 * decel);
  final d = (a.distanceMetres - brakingDistance).clamp(
    o.distanceMetres,
    a.distanceMetres,
  );
  final gap = a.distanceMetres - o.distanceMetres;
  final f = gap <= 0 ? 0.0 : (d - o.distanceMetres) / gap;
  return (distanceMetres: d, point: o.point + (a.point - o.point) * f);
}

/// Deceleration in g at sample [i], measured against the latest sample at
/// least [windowMicros] earlier (or the previous one at low GPS rates).
double _decelerationG(List<TraceSample> s, int i, int windowMicros) {
  var j = i - 1;
  while (j > 0 && s[i].timeMicros - s[j].timeMicros < windowMicros) {
    j--;
  }
  final dt = (s[i].timeMicros - s[j].timeMicros) / 1e6;
  if (dt <= 0) return 0;
  return (s[j].speedMetresPerSecond - s[i].speedMetresPerSecond) / dt / gravity;
}

/// Live deceleration (g) from the last two speed readings, used to notice
/// that the driver has started braking after a red alert.
double liveDecelerationG({
  required double previousSpeed,
  required double currentSpeed,
  required int elapsedMicros,
}) {
  if (elapsedMicros <= 0) return 0;
  return (previousSpeed - currentSpeed) / (elapsedMicros / 1e6) / gravity;
}
