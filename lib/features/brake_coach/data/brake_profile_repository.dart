import 'dart:async';

import 'package:lap_timer/core/storage/json_file_store.dart';
import 'package:lap_timer/features/brake_coach/domain/brake_profile.dart';

/// The single source of truth for saved brake profiles (one JSON file).
class BrakeProfileRepository {
  /// Stores profiles in the given JSON store.
  BrakeProfileRepository(this._store);

  static const String _fileName = 'brake_profiles.json';

  final JsonFileStore _store;
  final StreamController<List<BrakeProfile>> _changes =
      StreamController<List<BrakeProfile>>.broadcast();
  List<BrakeProfile>? _cache;

  /// Emits the current list, then every change.
  Stream<List<BrakeProfile>> watchAll() async* {
    yield await _load();
    yield* _changes.stream;
  }

  /// Inserts or replaces [profile].
  Future<void> save(BrakeProfile profile) async {
    await _persist([
      for (final p in await _load())
        if (p.id != profile.id) p,
      profile,
    ]);
  }

  /// Deletes the profile with [id].
  Future<void> delete(String id) async {
    await _persist([
      for (final p in await _load())
        if (p.id != id) p,
    ]);
  }

  Future<void> _persist(List<BrakeProfile> all) async {
    all.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    await _store.write(_fileName, [for (final p in all) p.toJson()]);
    final snapshot = List<BrakeProfile>.unmodifiable(all);
    _cache = snapshot;
    _changes.add(snapshot);
  }

  Future<List<BrakeProfile>> _load() async {
    final cached = _cache;
    if (cached != null) return cached;
    final json = await _store.read(_fileName);
    final all = json is List<Object?>
        ? [for (final raw in json) ?BrakeProfile.tryFromJson(raw)]
        : <BrakeProfile>[];
    _cache = List.unmodifiable(all);
    return all;
  }
}
