import 'package:go_router/go_router.dart';
import 'package:lap_timer/features/gps/presentation/gps_monitor_screen.dart';
import 'package:lap_timer/features/home/home_screen.dart';

/// Route paths, kept in one place so screens never hard-code strings.
abstract final class AppRoutes {
  /// Start screen.
  static const String home = '/';

  /// GPS diagnostics.
  static const String gpsMonitor = '/gps-monitor';
}

/// The app's single router.
final GoRouter appRouter = GoRouter(
  routes: [
    GoRoute(
      path: AppRoutes.home,
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: AppRoutes.gpsMonitor,
      builder: (context, state) => const GpsMonitorScreen(),
    ),
  ],
);
