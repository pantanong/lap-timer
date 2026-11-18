import 'dart:async';

import 'package:lap_timer/core/storage/json_file_store.dart';
import 'package:lap_timer/features/tracks/domain/track.dart';

/// The single source of truth for tracks.
///
/// Every change goes through [save] or [delete]: the file is written first,
/// then the new list is pushed to everyone watching [watchAll].
class TrackRepository {
  /// Stores tracks in the given JSON store; `seedTracks` are added the
  /// first time the app runs (e.g. the simulator circuit).
  TrackRepository(this._store, {this._seedTracks = const []});

  static const String _fileName = 'tracks.json';

  final JsonFileStore _store;
  final List<Track> _seedTracks;
  final StreamController<List<Track>> _changes =
      StreamController<List<Track>>.broadcast();
  List<Track>? _cache;

  /// Emits the current list, then every change.
  Stream<List<Track>> watchAll() async* {
    yield await _load();
    yield* _changes.stream;
  }

  /// Current list of tracks, sorted by name.
  Future<List<Track>> all() => _load();

  /// Finds a track by id.
  Future<Track?> byId(String id) async {
    for (final track in await _load()) {
      if (track.id == id) return track;
    }
    return null;
  }

  /// Inserts or replaces [track].
  Future<void> save(Track track) async {
    final tracks = [
      for (final t in await _load())
        if (t.id != track.id) t,
      track,
    ];
    await _persist(tracks);
  }

  /// Removes the track with [id].
  Future<void> delete(String id) async {
    final tracks = [
      for (final t in await _load())
        if (t.id != id) t,
    ];
    await _persist(tracks);
  }

  Future<void> _persist(List<Track> tracks) async {
    tracks.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    await _store.write(_fileName, [for (final t in tracks) t.toJson()]);
    final snapshot = List<Track>.unmodifiable(tracks);
    _cache = snapshot;
    _changes.add(snapshot);
  }

  Future<List<Track>> _load() async {
    final cached = _cache;
    if (cached != null) return cached;
    final json = await _store.read(_fileName);
    if (json is! List<Object?>) {
      // First run: start with the seed tracks.
      await _persist(List.of(_seedTracks));
      return _cache ?? const [];
    }
    final tracks = <Track>[for (final raw in json) ?Track.tryFromJson(raw)];
    _cache = List.unmodifiable(tracks);
    return tracks;
  }
}
