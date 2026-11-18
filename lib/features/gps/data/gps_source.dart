import 'package:lap_timer/core/result.dart';
import 'package:lap_timer/features/gps/domain/gps_fix.dart';

/// Where position data comes from. Every consumer (lap timing, pit mode,
/// brake coach) depends only on this interface, so a phone GPS, an external
/// 10–25 Hz receiver, the simulator or a replayed log are interchangeable.
abstract interface class GpsSource {
  /// Short human-readable name, e.g. "Phone GPS" or "Simulator".
  String get displayName;

  /// Asks for whatever the source needs before streaming (OS permission,
  /// Bluetooth connection, …). Safe to call more than once.
  Future<Result<void, GpsFailure>> prepare();

  /// Starts a new stream of fixes. Cancelling the subscription stops the
  /// source.
  Stream<GpsFix> fixes();
}

/// Expected reasons a [GpsSource] cannot deliver data.
enum GpsFailureKind {
  /// Location services are switched off on the device.
  serviceDisabled,

  /// The user refused location permission.
  permissionDenied,

  /// The user refused permission permanently; only Settings can fix it.
  permissionDeniedForever,

  /// The replay log is missing or unreadable.
  logUnavailable,
}

/// A failure from a [GpsSource].
class GpsFailure extends Failure {
  /// Creates a failure of [kind].
  const GpsFailure(this.kind, {super.cause});

  /// What went wrong.
  final GpsFailureKind kind;

  @override
  String get code => 'gps.${kind.name}';
}
