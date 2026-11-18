import 'dart:async';

import 'package:lap_timer/core/storage/json_file_store.dart';
import 'package:lap_timer/features/sessions/domain/session.dart';

/// The single source of truth for recorded sessions (one file each).
class SessionRepository {
  /// Stores sessions in the given JSON store.
  SessionRepository(this._store);

  final JsonFileStore _store;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Emits the session list now and after every change, newest first.
  Stream<List<Session>> watchAll() async* {
    yield await all();
    await for (final _ in _changes.stream) {
      yield await all();
    }
  }

  /// All sessions, newest first.
  Future<List<Session>> all() async {
    final sessions = <Session>[];
    for (final name in await _store.list()) {
      final session = Session.tryFromJson(await _store.read(name));
      if (session != null) sessions.add(session);
    }
    sessions.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return sessions;
  }

  /// Finds a session by id.
  Future<Session?> byId(String id) async =>
      Session.tryFromJson(await _store.read('$id.json'));

  /// Inserts or replaces [session]. Called after every lap during a
  /// session, so nothing is lost if the app is killed.
  Future<void> save(Session session) async {
    await _store.write('${session.id}.json', session.toJson());
    _changes.add(null);
  }

  /// Deletes the session with [id].
  Future<void> delete(String id) async {
    await _store.delete('$id.json');
    _changes.add(null);
  }
}
