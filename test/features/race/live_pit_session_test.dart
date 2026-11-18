import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lap_timer/app/infrastructure_providers.dart';
import 'package:lap_timer/core/storage/json_file_store.dart';
import 'package:lap_timer/features/gps/data/gps_log_repository.dart';
import 'package:lap_timer/features/gps/data/simulated_gps_source.dart';
import 'package:lap_timer/features/gps/gps_providers.dart';
import 'package:lap_timer/features/race/domain/race_rules.dart';
import 'package:lap_timer/features/sessions/data/session_repository.dart';
import 'package:lap_timer/features/sessions/domain/session.dart';
import 'package:lap_timer/features/timing/presentation/live_session_notifier.dart';
import 'package:lap_timer/features/timing/presentation/live_session_state.dart';
import 'package:lap_timer/features/tracks/data/simulator_track_preset.dart';
import 'package:lap_timer/features/tracks/data/track_repository.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('pit_test'));
  tearDown(() => dir.delete(recursive: true));

  Future<(LiveSessionState, List<LiveSessionState>)> runSession({
    required List<String> drivers,
    bool pressSameDriver = false,
  }) async {
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
            laps: 4,
            playbackSpeed: 400,
            pitStopAtCrossings: const {2},
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
      raceRules: const RaceRules(id: 'r', name: 'Test race'),
      drivers: drivers,
    );
    final seen = <LiveSessionState>[];
    final done = Completer<void>();
    container.listen(liveSessionProvider, (_, next) {
      seen.add(next);
      final pit = next.pit;
      if (pressSameDriver &&
          pit != null &&
          pit.showNextDriver &&
          !pit.sameDriver) {
        container.read(liveSessionProvider.notifier).keepSameDriver();
      }
      if (next.status == LiveSessionStatus.ended && !done.isCompleted) {
        done.complete();
      }
    });
    await container.read(liveSessionProvider.notifier).start();
    await done.future.timeout(const Duration(seconds: 30));
    return (container.read(liveSessionProvider), seen);
  }

  test(
    'solo driver: one pit stop, Nong(1) → Nong(2), pit laps excluded',
    () async {
      final (state, seen) = await runSession(drivers: const ['Nong']);
      expect(state.pitStops, hasLength(1));
      expect(state.pitStops.single.stopped, isTrue);
      expect(state.currentStint?.label, 'Nong(2)');
      // The next driver's name was shown while stopped.
      expect(seen.any((s) => s.pit?.showNextDriver ?? false), isTrue);
      expect(
        seen.map((s) => s.pit?.nextStintLabel).whereType<String>(),
        contains('Nong(2)'),
      );
      // The pit lane spans the start/finish line, so both the in-lap (2)
      // and the out-lap (3) include part of the stop: neither counts.
      expect(state.laps, hasLength(4));
      expect(state.racingLaps.map((l) => l.number), [1, 4]);
    },
  );

  test(
    'endurance: next driver takes over; Same driver keeps the driver',
    () async {
      final (rotated, _) = await runSession(drivers: const ['Nong', 'Ake']);
      expect(rotated.currentStint?.label, 'Ake(1)');

      final (kept, _) = await runSession(
        drivers: const ['Nong', 'Ake'],
        pressSameDriver: true,
      );
      expect(kept.currentStint?.label, 'Nong(2)');
    },
  );
}
