import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lap_timer/app/infrastructure_providers.dart';
import 'package:lap_timer/core/ui/page_padding.dart';
import 'package:lap_timer/features/tracks/data/track_editing.dart';
import 'package:lap_timer/features/tracks/domain/gate_line.dart';
import 'package:lap_timer/features/tracks/domain/line_ref.dart';
import 'package:lap_timer/features/tracks/domain/track.dart';
import 'package:lap_timer/features/tracks/presentation/position_capture_notifier.dart';
import 'package:lap_timer/features/tracks/presentation/text_prompt.dart';
import 'package:lap_timer/features/tracks/presentation/track_map_view.dart';
import 'package:lap_timer/l10n/generated/app_localizations.dart';
import 'package:lap_timer/theme/app_colors.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

/// Fine-tunes one timing line after it was set at the track: see and type
/// its coordinates, nudge it north/south/east/west, rotate it, change its
/// length, or tap the map to move it there.
///
/// Changes are a draft (drawn red over the saved line) until "Save", so
/// trying things out never loses the line collected at the track.
class LineEditorScreen extends ConsumerWidget {
  /// Edits the line [lineRef] of the track [trackId].
  const LineEditorScreen({
    required this.trackId,
    required this.lineRef,
    super.key,
  });

  /// Track being edited.
  final String trackId;

  /// Line being edited.
  final LineRef lineRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(tracksProvider).value ?? const <Track>[];
    final track = tracks.where((t) => t.id == trackId).firstOrNull;
    if (track == null) return const Scaffold();
    return _LineEditor(track: track, lineRef: lineRef);
  }
}

/// Display name of a line, e.g. "Start / Finish" or "Split 2".
String lineDisplayName(AppLocalizations l10n, LineRef ref) => switch (ref) {
  SingleLineRef(line: TrackLine.startFinish) => l10n.trackStartFinish,
  SingleLineRef(line: TrackLine.pitEntry) => l10n.trackPitEntry,
  SingleLineRef(line: TrackLine.pitExit) => l10n.trackPitExit,
  SplitLineRef(:final index) => l10n.trackSplitName(index + 1),
};

/// Coordinates as shown and typed: 6 decimals ≈ 0.1 m.
String formatCoordinates(double latitude, double longitude) =>
    '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';

/// Reads "lat, lon" (comma and/or spaces, as copied from Google Maps);
/// null when unreadable or out of range.
(double, double)? parseCoordinates(String text) {
  final parts = text
      .trim()
      .split(RegExp(r'[,\s]+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.length != 2) return null;
  final lat = double.tryParse(parts[0]);
  final lon = double.tryParse(parts[1]);
  if (lat == null || lon == null) return null;
  if (lat.abs() > 90 || lon.abs() > 180) return null;
  return (lat, lon);
}

class _LineEditor extends ConsumerStatefulWidget {
  const _LineEditor({required this.track, required this.lineRef});

  final Track track;
  final LineRef lineRef;

  @override
  ConsumerState<_LineEditor> createState() => _LineEditorState();
}

class _LineEditorState extends ConsumerState<_LineEditor> {
  late final GateLine? _saved = widget.track.lineAt(widget.lineRef);
  final MapController _map = MapController();
  late GateLine _draft = _saved ?? _startingPoint();
  late final TextEditingController _coordinates = TextEditingController(
    text: formatCoordinates(_draft.latitude, _draft.longitude),
  );
  double _stepMetres = 1;
  bool _badCoordinates = false;

  /// Where a line that was never set starts: the current GPS position, or
  /// the start/finish line, or the map's default.
  GateLine _startingPoint() {
    final fix = ref.read(positionCaptureProvider).latest;
    if (fix != null) {
      return GateLine(
        latitude: fix.latitude,
        longitude: fix.longitude,
        axisBearingDegrees: 0,
      );
    }
    final sf = widget.track.startFinish;
    return GateLine(
      latitude: sf?.latitude ?? 14.9605,
      longitude: sf?.longitude ?? 103.0845,
      axisBearingDegrees: 0,
    );
  }

  @override
  void dispose() {
    _coordinates.dispose();
    _map.dispose();
    super.dispose();
  }

  void _change(GateLine gate) => setState(() {
    _draft = gate;
    _badCoordinates = false;
    _coordinates.text = formatCoordinates(gate.latitude, gate.longitude);
  });

  void _applyTyped() {
    final parsed = parseCoordinates(_coordinates.text);
    if (parsed == null) {
      setState(() => _badCoordinates = true);
      return;
    }
    _change(_draft.movedTo(parsed.$1, parsed.$2));
    _map.move(LatLng(parsed.$1, parsed.$2), _map.camera.zoom);
  }

  void _useGps() {
    final fix = ref.read(positionCaptureProvider).latest;
    if (fix == null) return;
    _change(_draft.movedTo(fix.latitude, fix.longitude));
    _map.move(LatLng(fix.latitude, fix.longitude), _map.camera.zoom);
  }

  Future<void> _save() async {
    await ref
        .read(trackEditingProvider)
        .replaceLine(widget.track.id, widget.lineRef, _draft);
    if (mounted) context.pop();
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    if (!await confirm(context, l10n.lineEditorDeleteConfirm)) return;
    final editing = ref.read(trackEditingProvider);
    switch (widget.lineRef) {
      case SingleLineRef(:final line):
        await editing.clearLine(widget.track.id, line);
      case SplitLineRef(:final layoutId, :final index):
        await editing.removeSplit(widget.track.id, layoutId, index);
    }
    if (mounted) context.pop();
  }

  SectorLayout? get _layout => switch (widget.lineRef) {
    SplitLineRef(:final layoutId) =>
      widget.track.sectorLayouts.where((l) => l.id == layoutId).firstOrNull,
    SingleLineRef() => null,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final saved = _saved;
    final changed = _draft != saved;
    final mapHeight = MediaQuery.sizeOf(context).height * 0.42;
    return Scaffold(
      appBar: AppBar(
        title: Text(lineDisplayName(l10n, widget.lineRef)),
        actions: [
          if (_saved != null)
            IconButton(
              tooltip: l10n.actionDelete,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => unawaited(_delete()),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: mapHeight,
            child: TrackMapView(
              track: widget.track,
              sectorLayout: _layout,
              liveFix: ref.watch(positionCaptureProvider).latest,
              previewLine: _draft,
              previewLabel: switch (widget.lineRef) {
                SplitLineRef(:final index) => 'S${index + 1}|${index + 2}',
                SingleLineRef(line: TrackLine.startFinish) => 'S/F',
                SingleLineRef(line: TrackLine.pitEntry) => 'PIT IN',
                SingleLineRef(line: TrackLine.pitExit) => 'PIT OUT',
              },
              controller: _map,
              focus: LatLng(_draft.latitude, _draft.longitude),
              onTap: (p) => _change(_draft.movedTo(p.latitude, p.longitude)),
            ),
          ),
          Expanded(
            child: ListView(
              padding: pagePadding(context),
              children: [
                Text(l10n.lineEditorTapHint),
                const SizedBox(height: 12),
                _coordinateField(l10n),
                const SizedBox(height: 16),
                _MoveSection(
                  step: _stepMetres,
                  onStepChanged: (s) => setState(() => _stepMetres = s),
                  onMove: (east, north) => _change(
                    _draft.movedBy(
                      eastMetres: east * _stepMetres,
                      northMetres: north * _stepMetres,
                    ),
                  ),
                  onUseGps: _useGps,
                ),
                const SizedBox(height: 16),
                _RotateSection(
                  degrees: (_draft.lineAxisDegrees ?? 0).round() % 180,
                  onRotate: (d) => _change(_draft.rotatedBy(d)),
                ),
                const SizedBox(height: 16),
                _WidthSection(
                  metres: _draft.widthMetres.round(),
                  onChange: (d) =>
                      _change(_draft.withWidth(_draft.widthMetres + d)),
                ),
                const SizedBox(height: 20),
                if (changed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      l10n.lineEditorUnsaved,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.of(context).warning),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: changed && saved != null
                            ? () => _change(saved)
                            : null,
                        child: Text(l10n.lineEditorRevert),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: changed ? () => unawaited(_save()) : null,
                        child: Text(l10n.actionSave),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _coordinateField(AppLocalizations l10n) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: TextField(
          controller: _coordinates,
          keyboardType: const TextInputType.numberWithOptions(
            signed: true,
            decimal: true,
          ),
          decoration: InputDecoration(
            labelText: l10n.lineEditorCoordinates,
            helperText: l10n.lineEditorCoordinatesHelp,
            helperMaxLines: 2,
            errorText: _badCoordinates ? l10n.lineEditorBadCoordinates : null,
            errorMaxLines: 2,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _applyTyped(),
        ),
      ),
      const SizedBox(width: 8),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: FilledButton.tonal(
          onPressed: _applyTyped,
          child: Text(l10n.lineEditorApply),
        ),
      ),
    ],
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

/// Nudge pad (N/S/E/W by the chosen step) and "to my GPS position".
class _MoveSection extends StatelessWidget {
  const _MoveSection({
    required this.step,
    required this.onStepChanged,
    required this.onMove,
    required this.onUseGps,
  });

  final double step;
  final ValueChanged<double> onStepChanged;

  /// Called with (east, north) in steps: e.g. (0, 1) = one step north.
  final void Function(int east, int north) onMove;
  final VoidCallback onUseGps;

  static const List<double> _steps = [0.5, 1, 5];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget arrow(IconData icon, String tip, int east, int north) =>
        IconButton.filledTonal(
          tooltip: tip,
          iconSize: 28,
          icon: Icon(icon),
          onPressed: () => onMove(east, north),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(l10n.lineEditorMove),
        Row(
          children: [
            // Arrow pad: up = north, like the map.
            Column(
              children: [
                arrow(Icons.keyboard_arrow_up, l10n.lineEditorNorth, 0, 1),
                Row(
                  children: [
                    arrow(
                      Icons.keyboard_arrow_left,
                      l10n.lineEditorWest,
                      -1,
                      0,
                    ),
                    const SizedBox(width: 48),
                    arrow(
                      Icons.keyboard_arrow_right,
                      l10n.lineEditorEast,
                      1,
                      0,
                    ),
                  ],
                ),
                arrow(Icons.keyboard_arrow_down, l10n.lineEditorSouth, 0, -1),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<double>(
                    showSelectedIcon: false,
                    segments: [
                      for (final s in _steps)
                        ButtonSegment(
                          value: s,
                          label: Text(
                            '${s == s.roundToDouble() ? s.round() : s}',
                          ),
                        ),
                    ],
                    selected: {step},
                    onSelectionChanged: (s) => onStepChanged(s.first),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: onUseGps,
                    icon: const Icon(Icons.my_location),
                    label: Text(l10n.lineEditorUseGps),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Rotate buttons: 45° and 5° each way.
class _RotateSection extends StatelessWidget {
  const _RotateSection({required this.degrees, required this.onRotate});

  final int degrees;
  final ValueChanged<double> onRotate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget button(double d) => Expanded(
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
        onPressed: () => onRotate(d),
        icon: Icon(d < 0 ? Icons.rotate_left : Icons.rotate_right, size: 20),
        label: Text('${d.abs().round()}°'),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(l10n.lineEditorRotate(degrees)),
        Row(
          children: [
            button(-45),
            const SizedBox(width: 6),
            button(-5),
            const SizedBox(width: 6),
            button(5),
            const SizedBox(width: 6),
            button(45),
          ],
        ),
      ],
    );
  }
}

/// Line length −/+ 2 m.
class _WidthSection extends StatelessWidget {
  const _WidthSection({required this.metres, required this.onChange});

  final int metres;
  final ValueChanged<double> onChange;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(child: _SectionTitle(l10n.lineEditorWidth(metres))),
        IconButton.filledTonal(
          tooltip: l10n.lineEditorShorter,
          onPressed: () => onChange(-2),
          icon: const Icon(Icons.remove),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: l10n.lineEditorLonger,
          onPressed: () => onChange(2),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}
