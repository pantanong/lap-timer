import 'package:clock/clock.dart';
import 'package:lap_timer/core/result.dart';
import 'package:lap_timer/features/gps/data/gps_log_repository.dart';
import 'package:lap_timer/features/gps/data/gps_source.dart';
import 'package:lap_timer/features/gps/data/paced_fix_stream.dart';
import 'package:lap_timer/features/gps/domain/gps_fix.dart';

/// Plays a recorded raw GPS log back in real time, as if driving again.
class ReplayGpsSource implements GpsSource {
  /// Replays [log], reading it through the given log repository.
  ReplayGpsSource({
    required this.log,
    required this._repository,
    this.playbackSpeed = 1,
    this._clock = const Clock(),
  });

  /// The log to play.
  final GpsLogInfo log;

  /// 1 = real time; 4 = four times faster.
  final double playbackSpeed;

  final GpsLogRepository _repository;
  final Clock _clock;
  List<GpsFix> _fixes = const [];

  @override
  String get displayName => 'Replay: ${log.fileName}';

  @override
  Future<Result<void, GpsFailure>> prepare() async {
    final result = await _repository.readLog(log);
    switch (result) {
      case Ok(:final value) when value.isNotEmpty:
        _fixes = value;
        return const Ok(null);
      case Ok():
        return const Err(GpsFailure(GpsFailureKind.logUnavailable));
      case Err(:final failure):
        return Err(failure);
    }
  }

  @override
  Stream<GpsFix> fixes() =>
      pacedFixStream(_fixes, clock: _clock, playbackSpeed: playbackSpeed);
}
