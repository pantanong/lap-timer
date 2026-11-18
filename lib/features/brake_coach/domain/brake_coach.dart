import 'package:lap_timer/core/geo/local_point.dart';
import 'package:lap_timer/features/brake_coach/domain/brake_alert.dart';
import 'package:lap_timer/features/brake_coach/domain/brake_detection.dart';
import 'package:lap_timer/features/brake_coach/domain/brake_learning.dart';
import 'package:lap_timer/features/brake_coach/domain/brake_profile.dart';
import 'package:lap_timer/features/brake_coach/domain/lap_trace.dart';
import 'package:lap_timer/features/brake_coach/domain/reference_path.dart';
import 'package:lap_timer/features/gps/domain/gps_fix.dart';
import 'package:meta/meta.dart';

/// Brake coach options chosen when starting a session.
@immutable
class BrakeCoachSettings {
  /// Creates settings.
  const BrakeCoachSettings({
    this.learningLaps = 3,
    this.method = BrakeLearningMethod.fastestLap,
    this.alerts = const BrakeAlertSettings(),
    this.detection = const BrakeDetectionSettings(),
  });

  /// Racing laps to drive before alerts start (ignored with a saved
  /// profile).
  final int learningLaps;

  /// Method 1 or Method 2.
  final BrakeLearningMethod method;

  /// Alert timing.
  final BrakeAlertSettings alerts;

  /// Braking recognition thresholds.
  final BrakeDetectionSettings detection;
}

/// Where the coach is.
enum BrakeCoachPhase {
  /// Collecting learning laps.
  learning,

  /// Alerts are active.
  active,
}

/// The brake coach for one session: records each lap, learns the brake
/// points (or uses a saved profile), raises yellow/red alerts, and
/// collects how far off the driver braked for calibration suggestions.
///
/// Pure Dart; the live session feeds it fixes and lap events.
class BrakeCoach {
  /// Creates a coach. [projection] is the session's local plane (origin at
  /// the start/finish line). [startingProfile] skips the learning laps.
  BrakeCoach({
    required this.settings,
    required this.projection,
    BrakeProfile? startingProfile,
  }) {
    final profile = startingProfile;
    if (profile != null && profile.pathLatLng.length >= 2) {
      _path = ReferencePath([
        for (final (lat, lon) in profile.pathLatLng)
          projection.toLocal(lat, lon),
      ]);
      _corners = profile.corners;
      _fromSavedProfile = true;
      _armTracker();
    }
  }

  /// Options.
  final BrakeCoachSettings settings;

  /// Local plane of the session.
  final LocalProjection projection;

  static const int _maximumKeptLaps = 30;

  final List<LearningLap> _racingLaps = [];
  final Map<int, List<double>> _misses = {};
  List<TraceSample> _currentLap = [];
  double _odometer = 0;
  LocalPoint? _lastPoint;
  double? _pathDistance;
  bool _lapInProgress = false;

  ReferencePath? _path;
  List<CornerBrakePoint> _corners = const [];
  BrakeAlertTracker? _tracker;
  bool _fromSavedProfile = false;

  /// Learning or active.
  BrakeCoachPhase get phase =>
      _tracker == null ? BrakeCoachPhase.learning : BrakeCoachPhase.active;

  /// Racing laps recorded so far (for "learning 2/3").
  int get learnedLapCount => _racingLaps.length;

  /// Current corners (empty while learning).
  List<CornerBrakePoint> get corners => _corners;

  /// The reference path as (latitude, longitude), null while learning.
  List<(double, double)>? get pathLatLng {
    final path = _path;
    if (path == null) return null;
    return [for (final p in path.points) projection.toLatLng(p)];
  }

  /// Observed misses per corner (actual − learned brake point, metres).
  Map<int, List<double>> get misses => {
    for (final e in _misses.entries) e.key: List.unmodifiable(e.value),
  };

  /// Start/finish crossed: a new lap begins.
  void startLap() {
    _currentLap = [];
    _odometer = 0;
    _pathDistance = 0;
    _lapInProgress = true;
    _tracker?.startLap();
  }

  /// The lap that just ended (call before [startLap]). [isRacingLap] is
  /// false for laps through the pit lane: they are not learned from.
  void completeLap({
    required int lapNumber,
    required int lapTimeMicros,
    required bool isRacingLap,
  }) {
    final trace = LapTrace(List.unmodifiable(_currentLap));
    if (!isRacingLap || !trace.isUsable) return;
    _recordMisses(trace);
    _racingLaps.add(
      LearningLap(
        lapNumber: lapNumber,
        lapTimeMicros: lapTimeMicros,
        trace: trace,
      ),
    );
    if (_racingLaps.length > _maximumKeptLaps) _racingLaps.removeAt(0);
    final shouldLearn =
        !_fromSavedProfile &&
        (_tracker == null
            ? _racingLaps.length >= settings.learningLaps
            : settings.method == BrakeLearningMethod.deepestValid);
    if (shouldLearn) _learn();
  }

  /// Applies a corner edit made during the session (offset or lock).
  void replaceCorners(List<CornerBrakePoint> corners) {
    _corners = corners;
    if (_tracker != null) _armTracker();
  }

  /// Processes a fix and returns the alert to show.
  BrakeAlert addFix(GpsFix fix) {
    final point = projection.toLocal(fix.latitude, fix.longitude);
    final last = _lastPoint;
    _lastPoint = point;
    if (!_lapInProgress) return BrakeAlert.none;
    if (last != null) _odometer += point.distanceTo(last);
    _currentLap.add(
      TraceSample(
        timeMicros: fix.timestampMicros,
        distanceMetres: _odometer,
        speedMetresPerSecond: fix.speedMetresPerSecond,
        point: point,
      ),
    );
    final tracker = _tracker;
    final path = _path;
    if (tracker == null || path == null) return BrakeAlert.none;
    final located = path.locate(point, nearDistance: _pathDistance);
    // Far from the reference line (e.g. pit lane): no alerts.
    if (located == null || located.$2 > 30) return BrakeAlert.none;
    _pathDistance = located.$1;
    return tracker.update(
      distance: located.$1,
      speedMetresPerSecond: fix.speedMetresPerSecond,
      timeMicros: fix.timestampMicros,
    );
  }

  void _learn() {
    final learned = learnBrakePoints(
      laps: _racingLaps,
      detection: settings.detection,
      method: settings.method,
      projection: projection,
      locked: [
        for (final c in _corners)
          if (c.locked) c,
      ],
    );
    if (learned == null) return;
    // Keep user offsets of corners that stayed in place.
    final previous = _corners;
    _path = learned.path;
    _corners = learned.corners
        .map(
          (c) =>
              c.locked ? c : c.copyWith(offsetMetres: _offsetNear(previous, c)),
        )
        .toList();
    _armTracker();
  }

  static double _offsetNear(
    List<CornerBrakePoint> previous,
    CornerBrakePoint corner,
  ) {
    for (final p in previous) {
      if ((p.brakeDistanceMetres - corner.brakeDistanceMetres).abs() < 40) {
        return p.offsetMetres;
      }
    }
    return 0;
  }

  void _armTracker() {
    _tracker = BrakeAlertTracker(corners: _corners, settings: settings.alerts);
  }

  /// Compares where the driver actually braked with each learned point.
  void _recordMisses(LapTrace trace) {
    final path = _path;
    if (path == null || _tracker == null) return;
    final events = detectBrakeEvents(trace, settings.detection);
    for (var i = 0; i < _corners.length; i++) {
      final target = _corners[i].brakeDistanceMetres;
      double? best;
      for (final e in events) {
        final d = path.locate(e.onsetPoint)?.$1;
        if (d == null || (d - target).abs() > 40) continue;
        if (best == null || (d - target).abs() < (best - target).abs()) {
          best = d;
        }
      }
      if (best != null) (_misses[i] ??= []).add(best - target);
    }
  }
}
