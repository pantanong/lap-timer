import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lap_timer/features/brake_coach/data/brake_profile_repository.dart';
import 'package:lap_timer/features/brake_coach/domain/brake_profile.dart';
import 'package:lap_timer/features/race/data/race_rules_repository.dart';
import 'package:lap_timer/features/race/domain/race_rules.dart';
import 'package:lap_timer/features/sessions/data/session_repository.dart';
import 'package:lap_timer/features/sessions/domain/session.dart';
import 'package:lap_timer/features/tracks/data/track_repository.dart';
import 'package:lap_timer/features/tracks/domain/track.dart';

/// "Now". Always read time through this so tests can control it.
final Provider<Clock> clockProvider = Provider<Clock>((ref) => const Clock());

/// Track storage. Overridden in `main.dart` (needs the documents folder).
final Provider<TrackRepository> trackRepositoryProvider =
    Provider<TrackRepository>(
      (ref) => throw UnimplementedError('Override trackRepositoryProvider'),
    );

/// Session storage. Overridden in `main.dart`.
final Provider<SessionRepository> sessionRepositoryProvider =
    Provider<SessionRepository>(
      (ref) => throw UnimplementedError('Override sessionRepositoryProvider'),
    );

/// All tracks, updated live after every save.
final StreamProvider<List<Track>> tracksProvider = StreamProvider<List<Track>>(
  (ref) => ref.watch(trackRepositoryProvider).watchAll(),
);

/// All sessions, newest first, updated live.
final StreamProvider<List<Session>> sessionsProvider =
    StreamProvider<List<Session>>(
      (ref) => ref.watch(sessionRepositoryProvider).watchAll(),
    );

/// Race rule storage. Overridden in `main.dart`.
final Provider<RaceRulesRepository> raceRulesRepositoryProvider =
    Provider<RaceRulesRepository>(
      (ref) => throw UnimplementedError('Override raceRulesRepositoryProvider'),
    );

/// All race rule sets, updated live.
final StreamProvider<List<RaceRules>> raceRulesProvider =
    StreamProvider<List<RaceRules>>(
      (ref) => ref.watch(raceRulesRepositoryProvider).watchAll(),
    );

/// Brake profile storage. Overridden in `main.dart`.
final Provider<BrakeProfileRepository> brakeProfileRepositoryProvider =
    Provider<BrakeProfileRepository>(
      (ref) =>
          throw UnimplementedError('Override brakeProfileRepositoryProvider'),
    );

/// All saved brake profiles, updated live.
final StreamProvider<List<BrakeProfile>> brakeProfilesProvider =
    StreamProvider<List<BrakeProfile>>(
      (ref) => ref.watch(brakeProfileRepositoryProvider).watchAll(),
    );
