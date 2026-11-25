import 'dart:convert';

import 'package:lap_timer/features/tracks/domain/track.dart';

/// The file format used to export and import a track (with its timing
/// lines and sector layouts), e.g. to keep a backup on Google Drive or to
/// share a circuit with a team mate.
///
/// It is plain, indented JSON, readable by a person:
/// ```json
/// { "format": "lap-timer-track", "version": 1, "track": { ... } }
/// ```
abstract final class TrackFile {
  /// Value of the `format` field.
  static const String format = 'lap-timer-track';

  /// Current version of the format.
  static const int version = 1;

  /// Suggested file name for [track], e.g. `Buriram.laptrack.json`.
  static String fileNameFor(Track track) {
    final safe = track.name
        .replaceAll(RegExp(r'[^\w\- ]+', unicode: true), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    return '${safe.isEmpty ? 'track' : safe}.laptrack.json';
  }

  /// Encodes [track] as the file's text.
  static String encode(Track track) => const JsonEncoder.withIndent('  ')
      .convert({'format': format, 'version': version, 'track': track.toJson()});

  /// Decodes file text; returns null when it is not a valid track file
  /// (wrong format, newer version, or damaged).
  static Track? tryDecode(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, Object?>) return null;
    if (json['format'] != format) return null;
    final fileVersion = json['version'];
    if (fileVersion is! int || fileVersion > version) return null;
    return Track.tryFromJson(json['track']);
  }

  /// Prepares an imported [track] to be added next to [existing] ones: it
  /// gets a new id (so it never overwrites a track), and " (imported)" is
  /// added to its name if that name is already used.
  static Track asNewTrack(
    Track track,
    List<Track> existing, {
    required String newId,
  }) {
    final names = {for (final t in existing) t.name};
    var name = track.name;
    if (names.contains(name)) name = '$name (imported)';
    return Track(
      id: newId,
      name: name,
      startFinish: track.startFinish,
      sectorLayouts: track.sectorLayouts,
      defaultSectorLayoutId: track.defaultSectorLayoutId,
      pitEntry: track.pitEntry,
      pitExit: track.pitExit,
    );
  }
}
