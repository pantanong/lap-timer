import 'dart:async';

import 'package:lap_timer/core/storage/json_file_store.dart';
import 'package:lap_timer/features/race/domain/race_rules.dart';

/// The single source of truth for race rule sets (one JSON file).
class RaceRulesRepository {
  /// Stores rule sets in the given JSON store; on first run one default
  /// rule set is created.
  RaceRulesRepository(this._store);

  static const String _fileName = 'race_rules.json';

  /// Rule set created on first run (60 km/h limit, 1:00 minimum, 1 stop).
  static const RaceRules defaultRules = RaceRules(
    id: 'default-race',
    name: 'Race (60 km/h · 1:00 · 1 stop)',
  );

  final JsonFileStore _store;
  final StreamController<List<RaceRules>> _changes =
      StreamController<List<RaceRules>>.broadcast();
  List<RaceRules>? _cache;

  /// Emits the current list, then every change.
  Stream<List<RaceRules>> watchAll() async* {
    yield await _load();
    yield* _changes.stream;
  }

  /// Inserts or replaces [rules].
  Future<void> save(RaceRules rules) async {
    await _persist([
      for (final r in await _load())
        if (r.id != rules.id) r,
      rules,
    ]);
  }

  /// Deletes the rule set with [id].
  Future<void> delete(String id) async {
    await _persist([
      for (final r in await _load())
        if (r.id != id) r,
    ]);
  }

  Future<void> _persist(List<RaceRules> all) async {
    all.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    await _store.write(_fileName, [for (final r in all) r.toJson()]);
    final snapshot = List<RaceRules>.unmodifiable(all);
    _cache = snapshot;
    _changes.add(snapshot);
  }

  Future<List<RaceRules>> _load() async {
    final cached = _cache;
    if (cached != null) return cached;
    final json = await _store.read(_fileName);
    if (json is! List<Object?>) {
      await _persist([defaultRules]);
      return _cache ?? const [defaultRules];
    }
    final all = [for (final raw in json) ?RaceRules.tryFromJson(raw)];
    _cache = List.unmodifiable(all);
    return all;
  }
}
