import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lap_timer/app/infrastructure_providers.dart';
import 'package:lap_timer/app/routes.dart';
import 'package:lap_timer/core/ui/page_padding.dart';
import 'package:lap_timer/features/tracks/data/track_editing.dart';
import 'package:lap_timer/features/tracks/data/track_file_service.dart';
import 'package:lap_timer/features/tracks/domain/track.dart';
import 'package:lap_timer/features/tracks/domain/track_file.dart';
import 'package:lap_timer/l10n/generated/app_localizations.dart';
import 'package:lap_timer/theme/app_colors.dart';
import 'package:material_ui/material_ui.dart';

/// List of saved tracks; tap to edit, + to create.
class TracksScreen extends ConsumerWidget {
  /// Creates the screen.
  const TracksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tracks = ref.watch(tracksProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tracksTitle),
        actions: [
          TextButton.icon(
            onPressed: () => unawaited(_import(context, ref)),
            icon: const Icon(Icons.file_download_outlined),
            label: Text(l10n.tracksImportShort),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(_create(context, ref)),
        icon: const Icon(Icons.add),
        label: Text(l10n.tracksNew),
      ),
      body: switch (tracks) {
        AsyncData(:final value) => ListView(
          padding: pagePadding(context, hasFloatingButton: true),
          children: [
            for (final track in value) _TrackTile(track: track),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                l10n.tracksImportExportHint,
                style: TextStyle(color: AppColors.of(context).textMuted),
              ),
            ),
          ],
        ),
        AsyncError() => Center(child: Text(l10n.errorGeneric)),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  /// Picks a file exported by this app and adds it as a new track.
  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) =>
        messenger.showSnackBar(SnackBar(content: Text(text)));
    final String? text;
    try {
      text = await ref.read(trackFileServiceProvider).pickTrackFileText();
    } on Exception {
      say(l10n.tracksImportFailed);
      return;
    }
    if (text == null) return; // cancelled
    final decoded = TrackFile.tryDecode(text);
    if (decoded == null) {
      say(l10n.tracksImportFailed);
      return;
    }
    final existing = await ref.read(trackRepositoryProvider).all();
    final track = TrackFile.asNewTrack(
      decoded,
      existing,
      newId: 'track-${ref.read(clockProvider).now().microsecondsSinceEpoch}',
    );
    await ref.read(trackEditingProvider).importTrack(track);
    say(l10n.tracksImported(track.name));
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final now = ref.read(clockProvider).now();
    final track = Track(
      id: 'track-${now.microsecondsSinceEpoch}',
      name: l10n.tracksDefaultName,
    );
    await ref.read(trackRepositoryProvider).save(track);
    if (context.mounted) {
      unawaited(context.push(AppRoutes.trackEditor(track.id)));
    }
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final layouts = track.sectorLayouts.length;
    return Card(
      child: ListTile(
        title: Text(track.name),
        subtitle: Text(
          track.startFinish == null
              ? l10n.tracksNoStartFinish
              : l10n.tracksSummary(layouts),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(AppRoutes.trackEditor(track.id)),
      ),
    );
  }
}
