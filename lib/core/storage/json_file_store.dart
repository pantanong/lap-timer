import 'dart:convert';
import 'dart:io';

/// Reads and writes one JSON document per file, safely.
///
/// Writes go to a temporary file which is then renamed over the real one,
/// so a crash or a dead battery mid-write never leaves a half-written,
/// unreadable file behind.
class JsonFileStore {
  /// Stores files inside [directory] (created on demand).
  JsonFileStore(this.directory);

  /// Folder holding the JSON files.
  final Directory directory;

  File _file(String name) =>
      File('${directory.path}${Platform.pathSeparator}$name');

  /// Reads [name]; returns null when it does not exist or is not valid
  /// JSON.
  Future<Object?> read(String name) async {
    final file = _file(name);
    if (!file.existsSync()) return null;
    try {
      return jsonDecode(await file.readAsString());
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  /// Atomically replaces [name] with [json].
  Future<void> write(String name, Object? json) async {
    await directory.create(recursive: true);
    final target = _file(name);
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(jsonEncode(json), flush: true);
    await temp.rename(target.path);
  }

  /// Deletes [name] if present.
  Future<void> delete(String name) async {
    final file = _file(name);
    if (file.existsSync()) await file.delete();
  }

  /// Names of all `.json` files in the folder.
  Future<List<String>> list() async {
    if (!directory.existsSync()) return const [];
    final names = <String>[];
    await for (final entity in directory.list()) {
      final name = entity.path.split(Platform.pathSeparator).last;
      if (entity is File && name.endsWith('.json')) names.add(name);
    }
    return names;
  }
}
