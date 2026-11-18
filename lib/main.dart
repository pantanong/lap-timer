import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lap_timer/app/app.dart';
import 'package:lap_timer/app/infrastructure_providers.dart';
import 'package:lap_timer/core/storage/json_file_store.dart';
import 'package:lap_timer/features/gps/data/gps_log_repository.dart';
import 'package:lap_timer/features/gps/gps_providers.dart';
import 'package:lap_timer/features/race/data/race_rules_repository.dart';
import 'package:lap_timer/features/sessions/data/session_repository.dart';
import 'package:lap_timer/features/tracks/data/simulator_track_preset.dart';
import 'package:lap_timer/features/tracks/data/track_repository.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

/// App entry point (the composition root).
///
/// Order matters: error handlers first, then real infrastructure is built
/// and injected into Riverpod by overriding the placeholder providers.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught: $error\n$stack');
    return true;
  };

  final documents = await getApplicationDocumentsDirectory();
  final logRepository = GpsLogRepository(
    directory: Directory('${documents.path}/gps_logs'),
  );
  final trackRepository = TrackRepository(
    JsonFileStore(Directory('${documents.path}/tracks')),
    seedTracks: [simulatorTrackPreset()],
  );
  final raceRulesRepository = RaceRulesRepository(
    JsonFileStore(Directory('${documents.path}/race_rules')),
  );
  final sessionRepository = SessionRepository(
    JsonFileStore(Directory('${documents.path}/sessions')),
  );

  runApp(
    ProviderScope(
      overrides: [
        gpsLogRepositoryProvider.overrideWithValue(logRepository),
        trackRepositoryProvider.overrideWithValue(trackRepository),
        sessionRepositoryProvider.overrideWithValue(sessionRepository),
        raceRulesRepositoryProvider.overrideWithValue(raceRulesRepository),
      ],
      child: const LapTimerApp(),
    ),
  );
}
