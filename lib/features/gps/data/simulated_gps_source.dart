import 'package:clock/clock.dart';
import 'package:lap_timer/core/result.dart';
import 'package:lap_timer/features/gps/data/gps_source.dart';
import 'package:lap_timer/features/gps/data/paced_fix_stream.dart';
import 'package:lap_timer/features/gps/domain/gps_fix.dart';
import 'package:lap_timer/features/gps/domain/simulated_track.dart';

/// A virtual car lapping a virtual circuit in real time. Lets the whole app
/// (timing, pit mode, brake coach) be exercised at a desk, with no GPS.
class SimulatedGpsSource implements GpsSource {
  /// Creates a simulator driving [track] at [rateHz] for [laps] laps.
  SimulatedGpsSource({
    SimulatedTrack? track,
    this.rateHz = 10,
    this.laps = 20,
    this.playbackSpeed = 1,
    this.pitStopAtCrossings = const {3},
    this._clock = const Clock(),
  }) : track = track ?? SimulatedTrack();

  /// The circuit being driven.
  final SimulatedTrack track;

  /// Fixes per second.
  final double rateHz;

  /// Number of laps before the stream ends.
  final int laps;

  /// Start/finish crossings at which the car makes a pit stop.
  final Set<int> pitStopAtCrossings;

  /// 1 = real time; 2 = twice as fast, etc.
  final double playbackSpeed;

  final Clock _clock;

  @override
  String get displayName => 'Simulator (${rateHz.round()} Hz)';

  @override
  Future<Result<void, GpsFailure>> prepare() async => const Ok(null);

  @override
  Stream<GpsFix> fixes() => pacedFixStream(
    // A 45 s pit stop at the end of lap 3, to try pit mode at a desk.
    track.drive(
      laps: laps,
      rateHz: rateHz,
      pitStopAtCrossings: pitStopAtCrossings,
      pitStopSeconds: 45,
    ),
    clock: _clock,
    playbackSpeed: playbackSpeed,
  );
}
