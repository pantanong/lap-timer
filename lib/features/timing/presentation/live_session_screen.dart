import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lap_timer/core/screen_awake_service.dart';
import 'package:lap_timer/features/brake_coach/presentation/brake_alert_overlay.dart';
import 'package:lap_timer/features/gps/presentation/gps_failure_message.dart';
import 'package:lap_timer/features/race/presentation/pit_lane_view.dart';
import 'package:lap_timer/features/timing/presentation/live_session_notifier.dart';
import 'package:lap_timer/features/timing/presentation/live_session_state.dart';
import 'package:lap_timer/features/timing/presentation/live_timing_widgets.dart';
import 'package:lap_timer/l10n/generated/app_localizations.dart';
import 'package:lap_timer/theme/app_colors.dart';
import 'package:material_ui/material_ui.dart';

/// The in-car screen: landscape, screen always on, big numbers only.
///
/// Layout (see docs/mockups/11-sectors-running.png): running lap time and
/// predicted lap on top, one large box per sector in the middle, last/best
/// lap and compare mode at the bottom.
class LiveSessionScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const LiveSessionScreen({super.key});

  @override
  ConsumerState<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends ConsumerState<LiveSessionScreen> {
  late final ScreenAwakeService _screenAwake;

  @override
  void initState() {
    super.initState();
    _screenAwake = ref.read(screenAwakeServiceProvider);
    unawaited(_screenAwake.keepOn());
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(liveSessionProvider.notifier).start());
    });
  }

  @override
  void dispose() {
    unawaited(_screenAwake.release());
    unawaited(SystemChrome.setPreferredOrientations(const []));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  Future<void> _end() async {
    await ref.read(liveSessionProvider.notifier).end();
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(liveSessionProvider);
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.background,
      // The brake alert covers the whole screen, edge to edge.
      body: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 6, 20, 12),
              child: switch (state.status) {
                LiveSessionStatus.failed => _FailureView(state: state),
                _ when state.pit != null || state.pitResult != null =>
                  PitLaneView(state: state, onEnd: _end),
                _ => _TimingView(state: state, onEnd: _end),
              },
            ),
          ),
          BrakeAlertOverlay(alert: state.brakeAlert),
        ],
      ),
    );
  }
}

class _FailureView extends StatelessWidget {
  const _FailureView({required this.state});

  final LiveSessionState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final failure = state.failure;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            failure == null ? '' : gpsFailureMessage(l10n, failure),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.of(context).slower, fontSize: 20),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => context.pop(),
            child: Text(l10n.actionClose),
          ),
        ],
      ),
    );
  }
}

class _TimingView extends StatelessWidget {
  const _TimingView({required this.state, required this.onEnd});

  final LiveSessionState state;
  final Future<void> Function() onEnd;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LiveStatusBar(state: state, onEnd: onEnd),
      const SizedBox(height: 4),
      Expanded(flex: 5, child: LiveHeadline(state: state)),
      const SizedBox(height: 10),
      Expanded(flex: 4, child: SectorBoxesRow(state: state)),
      const SizedBox(height: 10),
      LiveFooter(state: state),
    ],
  );
}
