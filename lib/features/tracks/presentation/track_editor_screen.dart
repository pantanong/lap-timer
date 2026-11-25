import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lap_timer/app/infrastructure_providers.dart';
import 'package:lap_timer/app/routes.dart';
import 'package:lap_timer/core/ui/page_padding.dart';
import 'package:lap_timer/features/tracks/data/track_editing.dart';
import 'package:lap_timer/features/tracks/data/track_file_service.dart';
import 'package:lap_timer/features/tracks/domain/gate_line.dart';
import 'package:lap_timer/features/tracks/domain/line_ref.dart';
import 'package:lap_timer/features/tracks/domain/line_spacing.dart';
import 'package:lap_timer/features/tracks/domain/track.dart';
import 'package:lap_timer/features/tracks/presentation/position_capture_notifier.dart';
import 'package:lap_timer/features/tracks/presentation/sector_layout_card.dart';
import 'package:lap_timer/features/tracks/presentation/text_prompt.dart';
import 'package:lap_timer/features/tracks/presentation/track_map_view.dart';
import 'package:lap_timer/l10n/generated/app_localizations.dart';
import 'package:lap_timer/theme/app_colors.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

/// Edit a track: name, start/finish, pit lines and sector layouts.
///
/// Lines are set with "Set here" using live GPS (see
/// [PositionCaptureNotifier]): tap while driving slowly over the line, or
/// stand on it for ~10 s.
class TrackEditorScreen extends ConsumerWidget {
  /// Edits the track with [trackId].
  const TrackEditorScreen({required this.trackId, super.key});

  /// Track being edited.
  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tracks = ref.watch(tracksProvider).value ?? const <Track>[];
    final matches = tracks.where((t) => t.id == trackId);
    if (matches.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l10n.errorGeneric)),
      );
    }
    final track = matches.first;
    return Scaffold(
      appBar: AppBar(
        title: Text(track.name),
        actions: [
          IconButton(
            tooltip: l10n.trackExport,
            icon: const Icon(Icons.share),
            onPressed: () => unawaited(_export(context, ref, track)),
          ),
          IconButton(
            tooltip: l10n.actionRename,
            icon: const Icon(Icons.edit),
            onPressed: () => unawaited(_rename(context, ref, track)),
          ),
          IconButton(
            tooltip: l10n.actionDelete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => unawaited(_delete(context, ref)),
          ),
        ],
      ),
      body: ListView(
        padding: pagePadding(context),
        children: [
          _MapPreview(track: track),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => context.push(AppRoutes.trackMap(trackId)),
            icon: const Icon(Icons.edit_location_alt),
            label: Text(l10n.mapEditOnMap),
          ),
          const SizedBox(height: 12),
          const _GpsStatusCard(),
          const SizedBox(height: 12),
          _LineTile(
            trackId: trackId,
            line: TrackLine.startFinish,
            gate: track.startFinish,
          ),
          _LineTile(
            trackId: trackId,
            line: TrackLine.pitEntry,
            gate: track.pitEntry,
          ),
          _LineTile(
            trackId: trackId,
            line: TrackLine.pitExit,
            gate: track.pitExit,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.trackSectorLayouts,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final layout in track.sectorLayouts)
            SectorLayoutCard(track: track, layout: layout),
          OutlinedButton.icon(
            onPressed: () => unawaited(_addLayout(context, ref)),
            icon: const Icon(Icons.add),
            label: Text(l10n.trackAddLayout),
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref, Track track) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context).trackExportFailed;
    try {
      await ref.read(trackFileServiceProvider).export(track);
    } on Exception {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, Track track) async {
    final l10n = AppLocalizations.of(context);
    final name = await promptForText(
      context,
      title: l10n.actionRename,
      initial: track.name,
    );
    if (name == null || name.trim().isEmpty) return;
    await ref.read(trackEditingProvider).rename(trackId, name);
  }

  Future<void> _addLayout(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final name = await promptForText(context, title: l10n.trackAddLayout);
    if (name == null || name.trim().isEmpty) return;
    await ref.read(trackEditingProvider).addLayout(trackId, name);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final ok = await confirm(context, l10n.trackDeleteConfirm);
    if (!ok) return;
    await ref.read(trackEditingProvider).deleteTrack(trackId);
    if (context.mounted) context.pop();
  }
}

class _GpsStatusCard extends ConsumerWidget {
  const _GpsStatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final capture = ref.watch(positionCaptureProvider);
    final fix = capture.latest;
    final text = fix == null
        ? l10n.monitorWaiting
        : l10n.trackGpsStatus(
            fix.horizontalAccuracyMetres?.toStringAsFixed(1) ?? '?',
            fix.speedKmh.toStringAsFixed(0),
            capture.averagingSeconds.toStringAsFixed(0),
          );
    return Card(
      child: ListTile(
        leading: Icon(
          Icons.gps_fixed,
          color: fix == null ? colors.warning : colors.faster,
        ),
        title: Text(text),
        subtitle: Text(l10n.trackSetHereHint),
      ),
    );
  }
}

class _LineTile extends ConsumerWidget {
  const _LineTile({
    required this.trackId,
    required this.line,
    required this.gate,
  });

  final String trackId;
  final TrackLine line;
  final GateLine? gate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final title = switch (line) {
      TrackLine.startFinish => l10n.trackStartFinish,
      TrackLine.pitEntry => l10n.trackPitEntry,
      TrackLine.pitExit => l10n.trackPitExit,
    };
    final isSet = gate != null;
    return Card(
      child: ListTile(
        leading: Icon(
          isSet ? Icons.check_circle : Icons.radio_button_unchecked,
          color: isSet ? colors.faster : colors.textMuted,
        ),
        title: Text(title),
        subtitle: Text(switch (gate) {
          _? => l10n.trackLineTapToAdjust,
          null => l10n.trackLineNotSet,
        }),
        // Tap to fine-tune: type coordinates, nudge, rotate, or move it on
        // the map (also works for a line not set yet).
        onTap: () =>
            context.push(AppRoutes.trackLine(trackId, SingleLineRef(line))),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSet)
              IconButton(
                tooltip: l10n.trackClearLine,
                icon: const Icon(Icons.close),
                onPressed: () => unawaited(
                  ref.read(trackEditingProvider).clearLine(trackId, line),
                ),
              ),
            FilledButton(
              onPressed: () {
                final captured = ref
                    .read(positionCaptureProvider.notifier)
                    .capture();
                if (captured == null) return;
                unawaited(
                  ref
                      .read(trackEditingProvider)
                      .setLine(trackId, line, captured),
                );
              },
              child: Text(l10n.trackSetHere),
            ),
          ],
        ),
      ),
    );
  }
}

/// The track map in the editor: drag to look around (pinch to zoom),
/// choose which sector layout to show, jump back to all lines or to the
/// current position.
class _MapPreview extends ConsumerStatefulWidget {
  const _MapPreview({required this.track});

  final Track track;

  @override
  ConsumerState<_MapPreview> createState() => _MapPreviewState();
}

class _MapPreviewState extends ConsumerState<_MapPreview> {
  final MapController _controller = MapController();
  String? _layoutId;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  SectorLayout? get _layout {
    final layouts = widget.track.sectorLayouts;
    for (final l in layouts) {
      if (l.id == _layoutId) return l;
    }
    return widget.track.defaultSectorLayout;
  }

  void _showAll() {
    final fit = TrackMapView.fitFor(
      TrackMapView.linePoints(widget.track, _layout),
    );
    if (fit != null) {
      _controller.fitCamera(fit);
      return;
    }
    final points = TrackMapView.linePoints(widget.track, _layout);
    if (points.isNotEmpty) _controller.move(points.first, 18);
  }

  void _showMe() {
    final fix = ref.read(positionCaptureProvider).latest;
    if (fix == null) return;
    _controller.move(LatLng(fix.latitude, fix.longitude), 18);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final layout = _layout;
    final layouts = widget.track.sectorLayouts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 300,
            child: Stack(
              children: [
                TrackMapView(
                  track: widget.track,
                  sectorLayout: layout,
                  liveFix: ref.watch(positionCaptureProvider).latest,
                  controller: _controller,
                  panOnly: true,
                ),
                PositionedDirectional(
                  end: 8,
                  top: 8,
                  child: Column(
                    children: [
                      _MapButton(
                        icon: Icons.zoom_out_map,
                        tooltip: l10n.mapShowAllLines,
                        onPressed: _showAll,
                      ),
                      const SizedBox(height: 8),
                      _MapButton(
                        icon: Icons.my_location,
                        tooltip: l10n.mapShowMyPosition,
                        onPressed: _showMe,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (layouts.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final l in layouts)
                  ChoiceChip(
                    label: Text(l.name),
                    selected: l.id == layout?.id,
                    onSelected: (_) => setState(() => _layoutId = l.id),
                  ),
              ],
            ),
          ),
        _LineSpacingWarning(track: widget.track),
      ],
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.of(context).surface.withValues(alpha: 0.9),
    shape: const CircleBorder(),
    child: IconButton(tooltip: tooltip, icon: Icon(icon), onPressed: onPressed),
  );
}

/// Warns when lines sit on top of each other (a common setup mistake).
class _LineSpacingWarning extends StatelessWidget {
  const _LineSpacingWarning({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final close = findCloseLines(track);
    if (close.isEmpty) return const SizedBox.shrink();
    String name(NamedLine n) => switch (n.kind) {
      LineKind.startFinish => l10n.trackStartFinish,
      LineKind.pitEntry => l10n.trackPitEntry,
      LineKind.pitExit => l10n.trackPitExit,
      LineKind.split => l10n.trackSplitName((n.splitIndex ?? 0) + 1),
    };
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.trackLinesTooClose,
            style: TextStyle(
              color: colors.warning,
              fontWeight: FontWeight.w700,
            ),
          ),
          for (final c in close)
            Text(
              l10n.trackLinesTooClosePair(
                name(c.a),
                name(c.b),
                c.distanceMetres.round(),
              ),
            ),
        ],
      ),
    );
  }
}
