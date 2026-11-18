import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lap_timer/app/infrastructure_providers.dart';
import 'package:lap_timer/features/tracks/data/track_editing.dart';
import 'package:lap_timer/features/tracks/domain/gate_line.dart';
import 'package:lap_timer/features/tracks/domain/track.dart';
import 'package:lap_timer/features/tracks/presentation/position_capture_notifier.dart';
import 'package:lap_timer/features/tracks/presentation/sector_layout_card.dart';
import 'package:lap_timer/features/tracks/presentation/text_prompt.dart';
import 'package:lap_timer/l10n/generated/app_localizations.dart';
import 'package:lap_timer/theme/app_colors.dart';
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
        padding: const EdgeInsets.all(16),
        children: [
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
        subtitle: Text(isSet ? l10n.trackLineSet : l10n.trackLineNotSet),
        trailing: FilledButton(
          onPressed: () {
            final captured = ref
                .read(positionCaptureProvider.notifier)
                .capture();
            if (captured == null) return;
            unawaited(
              ref.read(trackEditingProvider).setLine(trackId, line, captured),
            );
          },
          child: Text(l10n.trackSetHere),
        ),
      ),
    );
  }
}
