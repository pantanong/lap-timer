import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:lap_timer/features/brake_coach/presentation/corners_screen.dart';
import 'package:lap_timer/features/gps/presentation/gps_monitor_screen.dart';
import 'package:lap_timer/features/home/home_screen.dart';
import 'package:lap_timer/features/race/presentation/race_rules_screen.dart';
import 'package:lap_timer/features/sessions/presentation/new_session_screen.dart';
import 'package:lap_timer/features/sessions/presentation/session_detail_screen.dart';
import 'package:lap_timer/features/sessions/presentation/sessions_screen.dart';
import 'package:lap_timer/features/timing/presentation/live_session_screen.dart';
import 'package:lap_timer/features/tracks/domain/line_ref.dart';
import 'package:lap_timer/features/tracks/presentation/line_editor_screen.dart';
import 'package:lap_timer/features/tracks/presentation/track_editor_screen.dart';
import 'package:lap_timer/features/tracks/presentation/track_map_screen.dart';
import 'package:lap_timer/features/tracks/presentation/tracks_screen.dart';

/// Route paths, kept in one place so screens never hard-code strings.
abstract final class AppRoutes {
  /// Start screen.
  static const String home = '/';

  /// GPS diagnostics.
  static const String gpsMonitor = '/gps-monitor';

  /// Session setup.
  static const String newSession = '/session/new';

  /// In-car timing screen.
  static const String live = '/session/live';

  /// Track list.
  static const String tracks = '/tracks';

  /// Race rule sets.
  static const String raceRules = '/race-rules';

  /// Session history.
  static const String sessions = '/sessions';

  /// Editor for one track.
  static String trackEditor(String trackId) => '/tracks/$trackId';

  /// Satellite map to place the lines of one track.
  static String trackMap(String trackId) => '/tracks/$trackId/map';

  /// Fine-tune one line of a track (coordinates, nudge, rotate).
  static String trackLine(String trackId, LineRef line) => Uri(
    path: '/tracks/$trackId/line',
    queryParameters: {'ref': line.encode()},
  ).toString();

  /// Detail of one session.
  static String sessionDetail(String sessionId) => '/sessions/$sessionId';

  /// Brake points (corners) of one session.
  static String corners(String sessionId) => '/sessions/$sessionId/corners';
}

/// The app's single router.
final GoRouter appRouter = GoRouter(
  routes: [
    GoRoute(path: AppRoutes.home, builder: (_, _) => const HomeScreen()),
    GoRoute(
      path: AppRoutes.gpsMonitor,
      builder: (_, _) => const GpsMonitorScreen(),
    ),
    GoRoute(
      path: AppRoutes.newSession,
      builder: (_, _) => const NewSessionScreen(),
    ),
    GoRoute(
      path: AppRoutes.raceRules,
      builder: (_, _) => const RaceRulesScreen(),
    ),
    GoRoute(path: AppRoutes.live, builder: (_, _) => const LiveSessionScreen()),
    GoRoute(
      path: AppRoutes.tracks,
      builder: (_, _) => const TracksScreen(),
      routes: [
        GoRoute(
          path: ':trackId',
          builder: (_, state) =>
              TrackEditorScreen(trackId: state.pathParameters['trackId'] ?? ''),
          routes: [
            GoRoute(
              path: 'map',
              builder: (_, state) => TrackMapScreen(
                trackId: state.pathParameters['trackId'] ?? '',
              ),
            ),
            GoRoute(
              path: 'line',
              builder: (_, state) {
                final line = LineRef.tryDecode(
                  state.uri.queryParameters['ref'],
                );
                if (line == null) return const SizedBox.shrink();
                return LineEditorScreen(
                  trackId: state.pathParameters['trackId'] ?? '',
                  lineRef: line,
                );
              },
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.sessions,
      builder: (_, _) => const SessionsScreen(),
      routes: [
        GoRoute(
          path: ':sessionId',
          builder: (_, state) => SessionDetailScreen(
            sessionId: state.pathParameters['sessionId'] ?? '',
          ),
          routes: [
            GoRoute(
              path: 'corners',
              builder: (_, state) => CornersScreen(
                sessionId: state.pathParameters['sessionId'] ?? '',
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);
