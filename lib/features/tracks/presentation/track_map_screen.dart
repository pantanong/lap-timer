import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lap_timer/app/infrastructure_providers.dart';
import 'package:lap_timer/features/tracks/data/track_editing.dart';
import 'package:lap_timer/features/tracks/domain/gate_line.dart';
import 'package:lap_timer/features/tracks/domain/track.dart';
import 'package:lap_timer/features/tracks/presentation/position_capture_notifier.dart';
import 'package:lap_timer/features/tracks/presentation/track_map_view.dart';
import 'package:lap_timer/l10n/generated/app_localizations.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

/// What the user is placing on the map.
@immutable
sealed class _PlacementTarget {
  const _PlacementTarget();
}

@immutable
final class _SingleLineTarget extends _PlacementTarget {
  const _SingleLineTarget(this.line);
  final TrackLine line;

  @override
  bool operator ==(Object other) =>
      other is _SingleLineTarget && other.line == line;

  @override
  int get hashCode => line.hashCode;
}

@immutable
final class _SplitTarget extends _PlacementTarget {
  const _SplitTarget(this.layoutId);
  final String layoutId;

  @override
  bool operator ==(Object other) =>
      other is _SplitTarget && other.layoutId == layoutId;

  @override
  int get hashCode => layoutId.hashCode;
}

/// Full-screen satellite map to place timing lines precisely: choose what
/// to place, tap one edge of the track, then the other, and save.
class TrackMapScreen extends ConsumerStatefulWidget {
  /// Edits the lines of the track with [trackId].
  const TrackMapScreen({required this.trackId, super.key});

  /// Track being edited.
  final String trackId;

  @override
  ConsumerState<TrackMapScreen> createState() => _TrackMapScreenState();
}

class _TrackMapScreenState extends ConsumerState<TrackMapScreen> {
  _PlacementTarget _target = const _SingleLineTarget(TrackLine.startFinish);
  final List<LatLng> _points = [];
  MapImagery _imagery = MapImagery.satellite;

  GateLine? get _preview => _points.length == 2
      ? GateLine.fromEndpoints(
          _points[0].latitude,
          _points[0].longitude,
          _points[1].latitude,
          _points[1].longitude,
        )
      : null;

  void _onTap(LatLng point) => setState(() {
    if (_points.length == 2) _points.clear();
    _points.add(point);
  });

  Future<void> _save() async {
    final gate = _preview;
    if (gate == null) return;
    final editing = ref.read(trackEditingProvider);
    switch (_target) {
      case _SingleLineTarget(:final line):
        await editing.setLine(widget.trackId, line, gate);
      case _SplitTarget(:final layoutId):
        await editing.addSplit(widget.trackId, layoutId, gate);
    }
    if (mounted) setState(_points.clear);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tracks = ref.watch(tracksProvider).value ?? const <Track>[];
    final matches = tracks.where((t) => t.id == widget.trackId);
    if (matches.isEmpty) return const Scaffold();
    final track = matches.first;
    final fix = ref.watch(positionCaptureProvider).latest;
    final target = _target;
    final layout = target is _SplitTarget
        ? track.sectorLayouts.where((l) => l.id == target.layoutId).firstOrNull
        : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(track.name),
        actions: [
          IconButton(
            tooltip: l10n.mapToggleImagery,
            icon: Icon(
              _imagery == MapImagery.satellite
                  ? Icons.map
                  : Icons.satellite_alt,
            ),
            onPressed: () => setState(
              () => _imagery = _imagery == MapImagery.satellite
                  ? MapImagery.street
                  : MapImagery.satellite,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: TrackMapView(
              track: track,
              sectorLayout: layout,
              liveFix: fix,
              pendingPoints: _points,
              previewLine: _preview,
              imagery: _imagery,
              onTap: _onTap,
            ),
          ),
          _PlacementPanel(
            track: track,
            target: _target,
            pointCount: _points.length,
            onTargetChanged: (t) => setState(() {
              _target = t;
              _points.clear();
            }),
            onUndo: () => setState(() {
              if (_points.isNotEmpty) _points.removeLast();
            }),
            onSave: () => unawaited(_save()),
          ),
        ],
      ),
    );
  }
}

class _PlacementPanel extends StatelessWidget {
  const _PlacementPanel({
    required this.track,
    required this.target,
    required this.pointCount,
    required this.onTargetChanged,
    required this.onUndo,
    required this.onSave,
  });

  final Track track;
  final _PlacementTarget target;
  final int pointCount;
  final ValueChanged<_PlacementTarget> onTargetChanged;
  final VoidCallback onUndo;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButton<_PlacementTarget>(
              isExpanded: true,
              value: target,
              items: [
                DropdownMenuItem(
                  value: const _SingleLineTarget(TrackLine.startFinish),
                  child: Text(l10n.trackStartFinish),
                ),
                DropdownMenuItem(
                  value: const _SingleLineTarget(TrackLine.pitEntry),
                  child: Text(l10n.trackPitEntry),
                ),
                DropdownMenuItem(
                  value: const _SingleLineTarget(TrackLine.pitExit),
                  child: Text(l10n.trackPitExit),
                ),
                for (final layout in track.sectorLayouts)
                  DropdownMenuItem(
                    value: _SplitTarget(layout.id),
                    child: Text(l10n.mapAddSplitTo(layout.name)),
                  ),
              ],
              onChanged: (t) => t == null ? null : onTargetChanged(t),
            ),
            Text(switch (pointCount) {
              0 => l10n.mapTapFirstEdge,
              1 => l10n.mapTapSecondEdge,
              _ => l10n.mapReadyToSave,
            }),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: pointCount == 0 ? null : onUndo,
                    child: Text(l10n.mapUndoPoint),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: pointCount == 2 ? onSave : null,
                    child: Text(l10n.mapSaveLine),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
