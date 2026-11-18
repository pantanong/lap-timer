import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:lap_timer/core/result.dart';
import 'package:lap_timer/features/gps/data/gps_source.dart';
import 'package:lap_timer/features/gps/domain/gps_fix.dart';

/// A raw GPS log on disk: one JSON object per line (NDJSON), one file per
/// recording. Raw logs are kept so any session can be replayed later to
/// debug timing, test the brake coach, or recompute sectors.
class GpsLogInfo {
  /// Describes the log at [path], created at [createdAt].
  const GpsLogInfo({required this.path, required this.createdAt});

  /// Absolute file path.
  final String path;

  /// When the recording started.
  final DateTime createdAt;

  /// File name without directory, e.g. `2026-11-18T09-30-00.ndjson`.
  String get fileName => path.split(Platform.pathSeparator).last;
}

/// Writes fixes to a log file while a recording is active.
class GpsLogWriter {
  GpsLogWriter._(this.info, this._sink);

  /// The log being written.
  final GpsLogInfo info;
  final IOSink _sink;
  int _pendingLines = 0;

  /// Appends one fix. Data is flushed every 50 fixes and on [close].
  Future<void> add(GpsFix fix) async {
    _sink.writeln(jsonEncode(fix.toJson()));
    _pendingLines++;
    if (_pendingLines >= 50) {
      _pendingLines = 0;
      await _sink.flush();
    }
  }

  /// Flushes and closes the file. Must be called when recording stops.
  Future<void> close() async {
    await _sink.flush();
    await _sink.close();
  }
}

/// The single place that creates, lists and reads raw GPS logs.
class GpsLogRepository {
  /// Stores logs inside [directory] (created on demand).
  GpsLogRepository({required this.directory, this._clock = const Clock()});

  /// Folder holding the `.ndjson` files.
  final Directory directory;
  final Clock _clock;

  /// Opens a new log file named after the current time.
  Future<GpsLogWriter> startRecording() async {
    await directory.create(recursive: true);
    final now = _clock.now();
    final stamp = now.toIso8601String().split('.').first.replaceAll(':', '-');
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      '$stamp.ndjson',
    );
    final info = GpsLogInfo(path: file.path, createdAt: now);
    return GpsLogWriter._(info, file.openWrite(mode: FileMode.append));
  }

  /// All logs, newest first.
  Future<List<GpsLogInfo>> listLogs() async {
    if (!directory.existsSync()) return const [];
    final logs = <GpsLogInfo>[];
    await for (final entity in directory.list()) {
      if (entity is File && entity.path.endsWith('.ndjson')) {
        final stat = entity.statSync();
        logs.add(GpsLogInfo(path: entity.path, createdAt: stat.modified));
      }
    }
    logs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return logs;
  }

  /// Reads every valid fix in [log]. Malformed lines are skipped.
  Future<Result<List<GpsFix>, GpsFailure>> readLog(GpsLogInfo log) async {
    try {
      final lines = await File(log.path).readAsLines();
      final fixes = <GpsFix>[];
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final decoded = jsonDecode(line);
        if (decoded is Map<String, Object?>) {
          final fix = GpsFix.tryFromJson(decoded);
          if (fix != null) fixes.add(fix);
        }
      }
      return Ok(fixes);
    } on FileSystemException catch (e) {
      return Err(GpsFailure(GpsFailureKind.logUnavailable, cause: e));
    } on FormatException catch (e) {
      return Err(GpsFailure(GpsFailureKind.logUnavailable, cause: e));
    }
  }
}
