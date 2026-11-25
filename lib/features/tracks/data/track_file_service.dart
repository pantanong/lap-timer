import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lap_timer/features/tracks/domain/track.dart';
import 'package:lap_timer/features/tracks/domain/track_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Moves track files in and out of the app (share sheet, file picker).
/// Behind an interface so screens can be tested without the platform.
abstract interface class TrackFileService {
  /// Writes [track] to a file and opens the share sheet (Drive, LINE,
  /// e-mail, Files…).
  Future<void> export(Track track);

  /// Lets the user pick a file; returns its text, or null if cancelled.
  Future<String?> pickTrackFileText();
}

/// Real implementation using `share_plus` and `file_picker`.
class PlatformTrackFileService implements TrackFileService {
  /// Creates the service.
  const PlatformTrackFileService();

  @override
  Future<void> export(Track track) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}${Platform.pathSeparator}${TrackFile.fileNameFor(track)}',
    );
    await file.writeAsString(TrackFile.encode(track), flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: track.name,
        text: track.name,
      ),
    );
  }

  @override
  Future<String?> pickTrackFileText() async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty) return null;
    final bytes = await picked.first.readAsBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }
}

/// The track file service in use.
final Provider<TrackFileService> trackFileServiceProvider =
    Provider<TrackFileService>((ref) => const PlatformTrackFileService());
