import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lap_timer/core/result.dart';
import 'package:lap_timer/features/gps/domain/gps_fix.dart';
import 'package:lap_timer/features/gps/gps_providers.dart';
import 'package:lap_timer/features/tracks/domain/gate_line.dart';
import 'package:meta/meta.dart';

/// Live GPS while editing a track, used by the "Set line here" buttons.
@immutable
class PositionCaptureState {
  /// Creates a state.
  const PositionCaptureState({
    this.recentFixes = const [],
    this.isReady = false,
  });

  /// Fixes from the last [PositionCaptureNotifier.window].
  final List<GpsFix> recentFixes;

  /// Whether the GPS source is streaming.
  final bool isReady;

  /// Latest fix, if any.
  GpsFix? get latest => recentFixes.isEmpty ? null : recentFixes.last;

  /// Seconds of data currently averaged when standing still.
  double get averagingSeconds {
    if (recentFixes.length < 2) return 0;
    return (recentFixes.last.timestampMicros -
            recentFixes.first.timestampMicros) /
        1e6;
  }
}

/// Streams the selected GPS source and turns "Set line here" taps into
/// [GateLine]s.
///
/// - Moving (> 3 m/s): the line is placed at the latest position, across
///   the current direction of travel. Ideal for a passenger tapping while
///   the car drives slowly over the line.
/// - Standing still: the position is averaged over the last 10 s for
///   accuracy; the direction is learned from the first crossing.
class PositionCaptureNotifier extends Notifier<PositionCaptureState> {
  /// How much history is averaged when standing still.
  static const Duration window = Duration(seconds: 10);

  static const double _movingSpeedMetresPerSecond = 3;

  StreamSubscription<GpsFix>? _subscription;

  @override
  PositionCaptureState build() {
    ref.onDispose(() => unawaited(_subscription?.cancel()));
    unawaited(_start());
    return const PositionCaptureState();
  }

  Future<void> _start() async {
    final source = ref.read(gpsSourceProvider);
    if (source == null) return;
    final prepared = await source.prepare();
    if (!ref.mounted || prepared is Err) return;
    _subscription = source.fixes().listen(_onFix);
    state = PositionCaptureState(recentFixes: state.recentFixes, isReady: true);
  }

  void _onFix(GpsFix fix) {
    final cutoff = fix.timestampMicros - window.inMicroseconds;
    state = PositionCaptureState(
      recentFixes: [
        for (final f in state.recentFixes)
          if (f.timestampMicros >= cutoff) f,
        fix,
      ],
      isReady: true,
    );
  }

  /// Builds a line at the current position, or null without GPS.
  GateLine? capture({double widthMetres = 24}) {
    final latest = state.latest;
    if (latest == null) return null;
    final heading = latest.headingDegrees;
    if (latest.speedMetresPerSecond > _movingSpeedMetresPerSecond &&
        heading != null) {
      return GateLine(
        latitude: latest.latitude,
        longitude: latest.longitude,
        travelBearingDegrees: heading,
        widthMetres: widthMetres,
      );
    }
    final fixes = state.recentFixes;
    final lat = fixes.fold<double>(0, (s, f) => s + f.latitude) / fixes.length;
    final lon = fixes.fold<double>(0, (s, f) => s + f.longitude) / fixes.length;
    return GateLine(latitude: lat, longitude: lon, widthMetres: widthMetres);
  }
}

/// Live position for the track editor; stops when the editor closes.
final NotifierProvider<PositionCaptureNotifier, PositionCaptureState>
positionCaptureProvider =
    NotifierProvider.autoDispose<PositionCaptureNotifier, PositionCaptureState>(
      PositionCaptureNotifier.new,
    );
