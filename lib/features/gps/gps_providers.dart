import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lap_timer/features/gps/data/gps_log_repository.dart';
import 'package:lap_timer/features/gps/data/gps_source.dart';
import 'package:lap_timer/features/gps/data/phone_gps_source.dart';
import 'package:lap_timer/features/gps/data/replay_gps_source.dart';
import 'package:lap_timer/features/gps/data/simulated_gps_source.dart';

/// Raw GPS log storage. Must be overridden at startup (it needs the app's
/// documents folder), see `bootstrap.dart`.
final gpsLogRepositoryProvider = Provider<GpsLogRepository>(
  (ref) => throw UnimplementedError('Override gpsLogRepositoryProvider'),
);

/// Which kind of GPS source the user picked.
sealed class GpsSourceChoice {
  const GpsSourceChoice();
}

/// Use the phone's own GPS.
final class PhoneGpsChoice extends GpsSourceChoice {
  /// Creates the choice.
  const PhoneGpsChoice();
}

/// Use the virtual car on the virtual track.
final class SimulatorGpsChoice extends GpsSourceChoice {
  /// Creates the choice.
  const SimulatorGpsChoice();
}

/// Replay a recorded log. [log] is null until the user selects one.
final class ReplayGpsChoice extends GpsSourceChoice {
  /// Creates the choice for [log].
  const ReplayGpsChoice([this.log]);

  /// The recording to play, if selected.
  final GpsLogInfo? log;
}

/// Holds the user's GPS source choice.
class GpsSourceChoiceNotifier extends Notifier<GpsSourceChoice> {
  @override
  GpsSourceChoice build() => const PhoneGpsChoice();

  /// The current choice.
  GpsSourceChoice get choice => state;

  /// Switches to [choice].
  set choice(GpsSourceChoice choice) => state = choice;
}

/// The current GPS source choice.
final gpsSourceChoiceProvider =
    NotifierProvider<GpsSourceChoiceNotifier, GpsSourceChoice>(
      GpsSourceChoiceNotifier.new,
    );

/// The concrete [GpsSource] for the current choice, or null when Replay is
/// chosen without a log.
final gpsSourceProvider = Provider<GpsSource?>((ref) {
  final choice = ref.watch(gpsSourceChoiceProvider);
  return switch (choice) {
    PhoneGpsChoice() => const PhoneGpsSource(),
    SimulatorGpsChoice() => SimulatedGpsSource(),
    ReplayGpsChoice(:final log?) => ReplayGpsSource(
      log: log,
      repository: ref.watch(gpsLogRepositoryProvider),
    ),
    ReplayGpsChoice() => null,
  };
});

/// All recorded logs, newest first. Invalidate after recording.
final gpsLogsProvider = FutureProvider<List<GpsLogInfo>>(
  (ref) => ref.watch(gpsLogRepositoryProvider).listLogs(),
);
