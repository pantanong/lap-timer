import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lap_timer/app/infrastructure_providers.dart';
import 'package:lap_timer/core/storage/json_file_store.dart';
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

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('live_session_test');
  });
  tearDown(() => dir.delete(recursive: true));

  ProviderContainer makeContainer() {
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
        // 3 simulated laps played 200x faster than real time.
        gpsSourceProvider.overrideWithValue(
          SimulatedGpsSource(
            laps: 3,
            playbackSpeed: 200,
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
      sectorLayout: track.defaultSectorLayout,
      vehicleType: VehicleType.car,
    );
    return container;
  }

  test(
    'a simulated session times 3 laps with 3 sectors and saves them',
    () async {
      final container = makeContainer();
      final sub = container.listen(liveSessionProvider, (_, _) {});
      addTearDown(sub.close);

      await container.read(liveSessionProvider.notifier).start();
      // Wait until the simulator stream ends (the session then ends itself).
      final done = Completer<void>();
      container.listen(liveSessionProvider, (_, next) {
        if (next.status == LiveSessionStatus.ended && !done.isCompleted) {
          done.complete();
        }
      });
      await done.future.timeout(const Duration(seconds: 30));

      final state = container.read(liveSessionProvider);
      expect(state.laps, hasLength(3));
      for (final lap in state.laps) {
        expect(lap.sectorMicros, hasLength(3));
        expect(lap.hasAllSectors, isTrue);
      }
      // Same simulated car every lap → identical lap times within 0.05 s.
      final times = state.laps.map((l) => l.timeMicros).toList();
      expect((times[1] - times[2]).abs(), lessThan(50000));

      final saved = await container.read(sessionRepositoryProvider).all();
      expect(saved, hasLength(1));
      expect(saved.single.laps, state.laps);
      expect(saved.single.gpsLogFileName, isNotNull);
    },
  );
}
