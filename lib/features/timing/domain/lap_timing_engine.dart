import 'dart:math' as math;

import 'package:lap_timer/core/geo/local_point.dart';
import 'package:lap_timer/features/gps/domain/gps_fix.dart';
import 'package:lap_timer/features/timing/domain/lap.dart';
import 'package:lap_timer/features/tracks/domain/gate_line.dart';

/// Something the timing engine detected while processing a fix.
sealed class TimingEvent {
  const TimingEvent();
}

/// The car crossed start/finish for the first time: lap 1 begins.
final class LapStarted extends TimingEvent {
  /// Creates the event.
  const LapStarted({required this.lapNumber, required this.atMicros});

  /// Number of the lap that just began.
  final int lapNumber;

  /// Interpolated crossing time.
  final int atMicros;
}

/// A sector of the current lap was completed.
final class SectorCompleted extends TimingEvent {
  /// Creates the event.
  const SectorCompleted({
    required this.lapNumber,
    required this.sectorIndex,
    required this.sectorMicros,
    required this.atMicros,
  });

  /// Lap the sector belongs to.
  final int lapNumber;

  /// 0-based sector index.
  final int sectorIndex;

  /// Sector time in microseconds.
  final int sectorMicros;

  /// Interpolated crossing time of the split line.
  final int atMicros;
}

/// A lap was completed (the next lap starts at the same instant).
final class LapCompleted extends TimingEvent {
  /// Creates the event.
  const LapCompleted(this.lap);

  /// The finished lap.
  final Lap lap;
}

/// Turns a stream of GPS fixes into laps and sector times.
///
/// How it works, for each new fix:
/// 1. The segment from the previous fix to this one is tested against the
///    start/finish line and the next expected split line.
/// 2. If it crosses a line, the exact crossing instant is interpolated
///    along the segment. This is why 1 Hz phone GPS can still time laps to
///    roughly ±0.1–0.3 s, and 10–25 Hz receivers to a few hundredths.
/// 3. Splits must be crossed in order; a missed split leaves that sector
///    unknown (null) but never loses the lap.
///
/// The engine is pure Dart and deterministic: the same fixes always give
/// the same laps, which makes it easy to test with recorded or simulated
/// data.
class LapTimingEngine {
  /// Creates an engine for [startFinish] and optional sector [splits].
  ///
  /// Start/finish crossings closer together than [minimumLapMicros] are
  /// ignored (protects against GPS jitter right on the line).
  LapTimingEngine({
    required GateLine startFinish,
    List<GateLine> splits = const [],
    this.minimumLapMicros = 10 * 1000000,
  }) : _projection = LocalProjection(
         originLatitude: startFinish.latitude,
         originLongitude: startFinish.longitude,
       ) {
    _startFinish = ProjectedGate(startFinish, _projection);
    _splits = [for (final s in splits) ProjectedGate(s, _projection)];
  }

  /// Minimum time between two start/finish crossings.
  final int minimumLapMicros;

  final LocalProjection _projection;
  late ProjectedGate _startFinish;
  late List<ProjectedGate> _splits;

  GpsFix? _previousFix;
  LocalPoint? _previousPoint;

  int _lapsCompleted = 0;
  int? _lapStartMicros;
  int? _lastSplitMicros;
  int _nextSplitIndex = 0;
  List<int?> _currentSectors = [];

  /// Number of sectors per lap.
  int get sectorCount => _splits.length + 1;

  /// Whether a lap is in progress (start/finish has been crossed once).
  bool get isLapInProgress => _lapStartMicros != null;

  /// Start time of the lap in progress, if any.
  int? get currentLapStartMicros => _lapStartMicros;

  /// Number of the lap in progress (or the next one to start).
  int get currentLapNumber => _lapsCompleted + 1;

  /// 0-based index of the sector being driven now.
  int get currentSectorIndex => _nextSplitIndex;

  /// Sector times completed so far in the current lap.
  List<int?> get currentLapSectors => List.unmodifiable(_currentSectors);

  /// Start time of the sector being driven now, if known.
  int? get currentSectorStartMicros => _lastSplitMicros;

  /// The lines as currently known, including any direction learned from
  /// the first crossing (worth saving back to the track).
  List<GateLine> get learnedSplits => [for (final s in _splits) s.gate];

  /// The start/finish line, including a learned direction.
  GateLine get learnedStartFinish => _startFinish.gate;

  /// Processes one fix and returns what happened (usually nothing).
  List<TimingEvent> add(GpsFix fix) {
    final point = _projection.toLocal(fix.latitude, fix.longitude);
    final previousFix = _previousFix;
    final previousPoint = _previousPoint;
    _previousFix = fix;
    _previousPoint = point;
    if (previousFix == null || previousPoint == null) return const [];
    if (fix.timestampMicros <= previousFix.timestampMicros) return const [];

    final events = <TimingEvent>[];
    final split = _expectedSplit;
    if (split != null) {
      final at = _crossingTime(split, previousPoint, point, previousFix, fix);
      if (at != null) events.add(_completeSector(at));
    }
    final finishAt = _crossingTime(
      _startFinish,
      previousPoint,
      point,
      previousFix,
      fix,
    );
    if (finishAt != null) events.addAll(_crossStartFinish(finishAt));
    return events;
  }

  ProjectedGate? get _expectedSplit =>
      isLapInProgress && _nextSplitIndex < _splits.length
      ? _splits[_nextSplitIndex]
      : null;

  int? _crossingTime(
    ProjectedGate gate,
    LocalPoint from,
    LocalPoint to,
    GpsFix fromFix,
    GpsFix toFix,
  ) {
    final fraction = gate.crossingFraction(from, to);
    if (fraction == null) return null;
    _learnDirection(gate, to - from);
    final span = toFix.timestampMicros - fromFix.timestampMicros;
    return fromFix.timestampMicros + (span * fraction).round();
  }

  /// Stores the travel direction of a line that was set while standing.
  void _learnDirection(ProjectedGate gate, LocalPoint move) {
    if (gate.travelDirection != null) return;
    final bearing = (_bearingDegrees(move) + 360) % 360;
    final learned = ProjectedGate(gate.gate.withBearing(bearing), _projection);
    if (identical(gate, _startFinish)) {
      _startFinish = learned;
    } else {
      final i = _splits.indexOf(gate);
      if (i >= 0) _splits[i] = learned;
    }
  }

  /// Compass bearing of a local vector: atan2(east, north), in degrees.
  static double _bearingDegrees(LocalPoint v) =>
      math.atan2(v.x, v.y) * 180 / math.pi;

  SectorCompleted _completeSector(int atMicros) {
    final start = _lastSplitMicros ?? atMicros;
    final sector = atMicros - start;
    final event = SectorCompleted(
      lapNumber: currentLapNumber,
      sectorIndex: _nextSplitIndex,
      sectorMicros: sector,
      atMicros: atMicros,
    );
    _currentSectors.add(sector);
    _lastSplitMicros = atMicros;
    _nextSplitIndex++;
    return event;
  }

  List<TimingEvent> _crossStartFinish(int atMicros) {
    final lapStart = _lapStartMicros;
    if (lapStart == null) {
      _beginLap(atMicros);
      return [LapStarted(lapNumber: currentLapNumber, atMicros: atMicros)];
    }
    if (atMicros - lapStart < minimumLapMicros) return const [];

    // The final sector ends at start/finish; earlier missed splits stay null.
    final sectors = List<int?>.of(_currentSectors);
    final lastSplit = _lastSplitMicros;
    final finalSectorKnown = _nextSplitIndex == _splits.length;
    while (sectors.length < sectorCount - 1) {
      sectors.add(null);
    }
    sectors.add(
      finalSectorKnown && lastSplit != null ? atMicros - lastSplit : null,
    );

    final lap = Lap(
      number: currentLapNumber,
      startMicros: lapStart,
      endMicros: atMicros,
      sectorMicros: sectors,
    );
    _lapsCompleted++;
    _beginLap(atMicros);
    return [
      LapCompleted(lap),
      LapStarted(lapNumber: currentLapNumber, atMicros: atMicros),
    ];
  }

  void _beginLap(int atMicros) {
    _lapStartMicros = atMicros;
    _lastSplitMicros = atMicros;
    _nextSplitIndex = 0;
    _currentSectors = [];
  }

  /// Forgets the lap in progress (e.g. after entering the pit lane), so
  /// the next start/finish crossing starts a fresh lap.
  void abandonCurrentLap() {
    _lapStartMicros = null;
    _lastSplitMicros = null;
    _nextSplitIndex = 0;
    _currentSectors = [];
  }
}
