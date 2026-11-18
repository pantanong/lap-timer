import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lap_timer/app/app.dart';
import 'package:lap_timer/features/gps/data/gps_log_repository.dart';
import 'package:lap_timer/features/gps/gps_providers.dart';
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

  runApp(
    ProviderScope(
      overrides: [gpsLogRepositoryProvider.overrideWithValue(logRepository)],
      child: const LapTimerApp(),
    ),
  );
}
