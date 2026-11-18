import 'package:lap_timer/features/brake_coach/domain/brake_detection.dart';
import 'package:lap_timer/features/brake_coach/domain/brake_profile.dart';
import 'package:meta/meta.dart';

/// What the screen shows for the brake coach.
enum BrakeAlertPhase {
  /// Nothing.
  none,

  /// Yellow: a brake point is coming.
  approaching,

  /// Red: brake now.
  brakeNow,
}

/// Timing of the alerts.
@immutable
class BrakeAlertSettings {
  /// Creates settings.
  const BrakeAlertSettings({
    this.leadTime = const Duration(milliseconds: 700),
    this.yellowTime = const Duration(milliseconds: 2500),
    this.redTimeout = const Duration(seconds: 3),
    this.brakingG = 0.3,
  });

  /// Red appears this long before the brake point (reaction time + GPS
  /// delay), converted to metres with the current speed.
  final Duration leadTime;

  /// Yellow appears this long before red.
  final Duration yellowTime;

  /// Red disappears after this long even if no braking is detected.
  final Duration redTimeout;

  /// Deceleration that ends the red alert (driver is braking).
  final double brakingG;
}

/// The alert to display right now.
@immutable
class BrakeAlert {
  /// Creates an alert.
  const BrakeAlert({
    required this.phase,
    this.cornerIndex,
    this.metresToBrakePoint,
  });

  /// No alert.
  static const BrakeAlert none = BrakeAlert(phase: BrakeAlertPhase.none);

  /// Phase.
  final BrakeAlertPhase phase;

  /// 0-based corner the alert is for.
  final int? cornerIndex;

  /// Distance left to the brake point (for the yellow screen).
  final double? metresToBrakePoint;
}

/// Decides, fix by fix, whether to show nothing, yellow or red.
///
/// For the next corner: red starts at `brake point + corner offset − lead
/// time × speed`; yellow starts `yellow time × speed` before that. Red
/// stays until the driver brakes (deceleration ≥ threshold), the car is
/// well past the brake point, or the timeout expires. Then the next corner
/// is armed.
class BrakeAlertTracker {
  /// Creates a tracker for [corners] (driving order).
  BrakeAlertTracker({required this.corners, required this.settings});

  /// Corners to warn for.
  final List<CornerBrakePoint> corners;

  /// Alert timing.
  final BrakeAlertSettings settings;

  int _next = 0;
  int? _redSinceMicros;
  double? _lastSpeed;
  int? _lastTimeMicros;

  /// Arms the first corner again (call at every start/finish crossing).
  void startLap() {
    _next = 0;
    _redSinceMicros = null;
  }

  /// Updates with the car at [distance] metres along the reference path.
  BrakeAlert update({
    required double distance,
    required double speedMetresPerSecond,
    required int timeMicros,
  }) {
    final braking = _isBraking(speedMetresPerSecond, timeMicros);
    while (_next < corners.length) {
      final corner = corners[_next];
      final target = corner.brakeDistanceMetres;
      // Corner already behind us (e.g. GPS gap): move on.
      if (distance > target + 40) {
        _advance();
        continue;
      }
      final lead =
          speedMetresPerSecond * settings.leadTime.inMicroseconds / 1e6;
      final redAt = target + corner.offsetMetres - lead;
      final yellowAt =
          redAt -
          speedMetresPerSecond * settings.yellowTime.inMicroseconds / 1e6;
      if (distance < yellowAt) return BrakeAlert.none;
      if (distance < redAt && _redSinceMicros == null) {
        return BrakeAlert(
          phase: BrakeAlertPhase.approaching,
          cornerIndex: _next,
          metresToBrakePoint: target - distance,
        );
      }
      final since = _redSinceMicros ??= timeMicros;
      final timedOut = timeMicros - since > settings.redTimeout.inMicroseconds;
      if (braking || timedOut) {
        _advance();
        continue;
      }
      return BrakeAlert(phase: BrakeAlertPhase.brakeNow, cornerIndex: _next);
    }
    return BrakeAlert.none;
  }

  void _advance() {
    _next++;
    _redSinceMicros = null;
  }

  bool _isBraking(double speed, int timeMicros) {
    final lastSpeed = _lastSpeed;
    final lastTime = _lastTimeMicros;
    _lastSpeed = speed;
    _lastTimeMicros = timeMicros;
    if (lastSpeed == null || lastTime == null) return false;
    return liveDecelerationG(
          previousSpeed: lastSpeed,
          currentSpeed: speed,
          elapsedMicros: timeMicros - lastTime,
        ) >=
        settings.brakingG;
  }
}

/// A suggested change of one corner's alert, from repeated observations.
@immutable
class CalibrationSuggestion {
  /// Creates a suggestion.
  const CalibrationSuggestion({
    required this.cornerIndex,
    required this.typicalMissMetres,
    required this.lapsObserved,
    required this.lapsAgreeing,
  });

  /// Corner concerned.
  final int cornerIndex;

  /// Median of (actual brake point − learned brake point): positive = the
  /// driver braked later than the target.
  final double typicalMissMetres;

  /// Laps looked at.
  final int lapsObserved;

  /// Laps that missed in the same direction by more than the tolerance.
  final int lapsAgreeing;

  /// Proposed new offset change, rounded to 5 m: braking late → warn
  /// earlier (negative), braking early → warn later (positive).
  double get suggestedOffsetChangeMetres =>
      -(typicalMissMetres / 5).round() * 5.0;
}

/// Looks at the last [window] laps of each corner: if at least
/// [minimumAgreeing] of them missed the brake point in the same direction
/// by more than [toleranceMetres], suggests moving the alert. Never applied
/// automatically.
List<CalibrationSuggestion> calibrationSuggestions(
  Map<int, List<double>> missesByCorner, {
  int window = 5,
  int minimumAgreeing = 3,
  double toleranceMetres = 8,
}) {
  final result = <CalibrationSuggestion>[];
  for (final MapEntry(key: corner, value: all) in missesByCorner.entries) {
    final recent = all.length > window ? all.sublist(all.length - window) : all;
    final late = recent.where((m) => m > toleranceMetres).length;
    final early = recent.where((m) => m < -toleranceMetres).length;
    final agreeing = late > early ? late : early;
    if (agreeing < minimumAgreeing) continue;
    final sorted = List<double>.of(recent)..sort();
    final median = sorted[sorted.length ~/ 2];
    result.add(
      CalibrationSuggestion(
        cornerIndex: corner,
        typicalMissMetres: median,
        lapsObserved: recent.length,
        lapsAgreeing: agreeing,
      ),
    );
  }
  result.sort((a, b) => a.cornerIndex.compareTo(b.cornerIndex));
  return result;
}
