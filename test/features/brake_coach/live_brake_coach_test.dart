import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lap_timer/app/infrastructure_providers.dart';
import 'package:lap_timer/core/storage/json_file_store.dart';
import 'package:lap_timer/features/brake_coach/domain/brake_alert.dart';
import 'package:lap_timer/features/brake_coach/domain/brake_coach.dart';
import 'package:lap_timer/features/gps/data/gps_log_repository.dart';
import 'package:lap_timer/features/gps/data/simulated_gps_source.dart';
import 'package:lap_timer/features/gps/gps_providers.dart';
import 'package:lap_timer/features/sessions/data/session_repository.dart';
import 'package:lap_timer/features/sessions/domain/session.dart';
import 'package:lap_timer/features/timing/presentation/live_session_notifier.dart';
import 'package:lap_timer/features/timing/presentation/live_session_state.dart';
import 'package:lap_timer/features/tracks/data/simulator_track_preset.dart';
import 'package:lap_timer/features/tracks/data/track_repository.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('brake_test'));
  tearDown(() => dir.delete(recursive: true));

  Future<(ProviderContainer, List<LiveSessionState>)> run(
    VehicleType vehicle,
  ) async {
    final container = ProviderContainer.test(
      overrides: [
        gpsLogRepositoryProvider.overrideWithValue(
          GpsLogRepository(directory: Directory('${dir.path}/logs')),
        ),
        trackRepositoryProvider.overrideWithValue(
          TrackRepository(JsonFileStore(Directory('${dir.path}/tracks'))),
        ),
        sessionRepositoryProvider.overrideWithValue(
          SessionRepository(JsonFileStore(Directory('${dir.path}/sessions'))),
        ),
        gpsSourceProvider.overrideWithValue(
          SimulatedGpsSource(
            laps: 6,
            playbackSpeed: 400,
            pitStopAtCrossings: const {},
          ),
        ),
      ],
    );
    final track = simulatorTrackPreset();
    container
        .read(pendingSessionConfigProvider.notifier)
        .config = LiveSessionConfig(
      track: track,
      vehicleType: vehicle,
      brakeCoach: const BrakeCoachSettings(),
    );
    final seen = <LiveSessionState>[];
    final done = Completer<void>();
    container.listen(liveSessionProvider, (_, next) {
      seen.add(next);
      if (next.status == LiveSessionStatus.ended && !done.isCompleted) {
        done.complete();
      }
    });
    await container.read(liveSessionProvider.notifier).start();
    await done.future.timeout(const Duration(seconds: 30));
    return (container, seen);
  }

  test('car: learns 3 laps, then alerts; brake points saved with the '
      'session', () async {
    final (container, seen) = await run(VehicleType.car);
    final last = seen.last;
    expect(last.brakeCoachPhase, BrakeCoachPhase.active);
    expect(
      seen.any((s) => s.brakeAlert.phase == BrakeAlertPhase.approaching),
      isTrue,
    );
    expect(
      seen.any((s) => s.brakeAlert.phase == BrakeAlertPhase.brakeNow),
      isTrue,
    );
    final saved =
        (await container.read(sessionRepositoryProvider).all()).single;
    expect(saved.brakeProfile?.corners, hasLength(2));
    // Laps 4–6 were compared with the learned points.
    expect(saved.brakeMisses.values.expand((m) => m), isNotEmpty);
    for (final miss in saved.brakeMisses.values.expand((m) => m)) {
      expect(miss.abs(), lessThan(5));
    }
  });

  test('bicycle: the brake coach never runs', () async {
    final (_, seen) = await run(VehicleType.bicycle);
    expect(seen.every((s) => s.brakeCoachPhase == null), isTrue);
    expect(
      seen.every((s) => s.brakeAlert.phase == BrakeAlertPhase.none),
      isTrue,
    );
  });
}
