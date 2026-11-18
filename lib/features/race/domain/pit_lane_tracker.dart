import 'dart:math' as math;

import 'package:lap_timer/core/geo/local_point.dart';
import 'package:lap_timer/features/gps/domain/gps_fix.dart';
import 'package:lap_timer/features/race/domain/pit_stop.dart';
import 'package:lap_timer/features/tracks/domain/gate_line.dart';

/// Where the car is relative to the pit lane.
enum PitPhase {
  /// On track.
  onTrack,

  /// Between the pit entry and pit exit lines.
  inPitLane,
}

/// Something the pit lane tracker detected.
sealed class PitEvent {
  const PitEvent();
}

/// The car crossed the pit entry line.
final class PitEntered extends PitEvent {
  /// Creates the event.
  const PitEntered(this.atMicros);

  /// Interpolated crossing time.
  final int atMicros;
}

/// The car crossed the pit exit line (or the stop was closed by the
/// fallback, see [PitLaneTracker.closeIfStillInPit]).
final class PitExited extends PitEvent {
  /// Creates the event.
  const PitExited(this.stop);

  /// The completed pit stop.
  final PitStop stop;
}

/// Follows the car through the pit lane using the pit entry and exit
/// lines, measures the time spent and the highest speed, and estimates
/// the time at the exit line.
///
/// Pure Dart and deterministic, like the lap timing engine.
class PitLaneTracker {
  /// Creates a tracker for the given pit lane lines.
  PitLaneTracker({required GateLine pitEntry, required GateLine pitExit})
    : _projection = LocalProjection(
        originLatitude: pitEntry.latitude,
        originLongitude: pitEntry.longitude,
      ) {
    _entry = ProjectedGate(pitEntry, _projection);
    _exit = ProjectedGate(pitExit, _projection);
  }

  /// Speed below which the car counts as stopped (GPS noise at standstill
  /// is typically 1–2 km/h).
  static const double stoppedSpeedKmh = 3;

  final LocalProjection _projection;
  late ProjectedGate _entry;
  late ProjectedGate _exit;

  GpsFix? _previousFix;
  LocalPoint? _previousPoint;
  LocalPoint? _currentPoint;

  PitPhase _phase = PitPhase.onTrack;
  int? _entryMicros;
  double _maxSpeedKmh = 0;
  bool _stopped = false;
  int _stopsCompleted = 0;

  /// Current phase.
  PitPhase get phase => _phase;

  /// Pit entry crossing time while in the pit lane.
  int? get entryMicros => _entryMicros;

  /// Highest speed since the pit entry.
  double get maxSpeedKmh => _maxSpeedKmh;

  /// Whether the car has stopped since the pit entry.
  bool get hasStopped => _stopped;

  /// Completed pit stops so far.
  int get stopsCompleted => _stopsCompleted;

  /// Straight-line distance in metres from the car to the pit exit line.
  double? get distanceToExitMetres {
    return _currentPoint?.distanceTo(_exit.centre);
  }

  /// Processes one fix and returns what happened.
  List<PitEvent> add(GpsFix fix) {
    final point = _projection.toLocal(fix.latitude, fix.longitude);
    final previousFix = _previousFix;
    final previousPoint = _previousPoint;
    _previousFix = fix;
    _previousPoint = point;
    _currentPoint = point;
    if (_phase == PitPhase.inPitLane) {
      _maxSpeedKmh = math.max(_maxSpeedKmh, fix.speedKmh);
      if (fix.speedKmh < stoppedSpeedKmh) _stopped = true;
    }
    if (previousFix == null || previousPoint == null) return const [];
    final span = fix.timestampMicros - previousFix.timestampMicros;
    if (span <= 0) return const [];

    final gate = _phase == PitPhase.onTrack ? _entry : _exit;
    final fraction = gate.crossingFraction(previousPoint, point);
    if (fraction == null) return const [];
    final at = previousFix.timestampMicros + (span * fraction).round();
    _learnDirection(gate, point - previousPoint);

    if (_phase == PitPhase.onTrack) {
      _phase = PitPhase.inPitLane;
      _entryMicros = at;
      _maxSpeedKmh = fix.speedKmh;
      _stopped = false;
      return [PitEntered(at)];
    }
    return [PitExited(_finish(at))];
  }

  /// Fallback when the exit line was missed (e.g. GPS dropout): closes the
  /// stop at [atMicros] if the car is still marked as in the pit lane.
  PitStop? closeIfStillInPit(int atMicros) {
    if (_phase != PitPhase.inPitLane) return null;
    return _finish(atMicros);
  }

  /// Estimated pit time when the car reaches the exit line, if it keeps
  /// its current speed. Null when stopped or unknown.
  int? projectedPitMicrosAtExit(int nowMicros, double speedKmh) {
    final entry = _entryMicros;
    final distance = distanceToExitMetres;
    if (entry == null || distance == null || speedKmh < stoppedSpeedKmh) {
      return null;
    }
    final secondsToExit = distance / (speedKmh / 3.6);
    return nowMicros - entry + (secondsToExit * 1e6).round();
  }

  PitStop _finish(int atMicros) {
    _stopsCompleted++;
    final stop = PitStop(
      number: _stopsCompleted,
      entryMicros: _entryMicros ?? atMicros,
      exitMicros: atMicros,
      maxSpeedKmh: _maxSpeedKmh,
      stopped: _stopped,
    );
    _phase = PitPhase.onTrack;
    _entryMicros = null;
    return stop;
  }

  void _learnDirection(ProjectedGate gate, LocalPoint move) {
    if (gate.travelDirection != null) return;
    final bearing = (math.atan2(move.x, move.y) * 180 / math.pi + 360) % 360;
    final learned = ProjectedGate(gate.gate.withBearing(bearing), _projection);
    if (identical(gate, _entry)) {
      _entry = learned;
    } else {
      _exit = learned;
    }
  }
}
