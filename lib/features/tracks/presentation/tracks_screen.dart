import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lap_timer/app/infrastructure_providers.dart';
import 'package:lap_timer/app/routes.dart';
import 'package:lap_timer/features/tracks/domain/track.dart';
import 'package:lap_timer/l10n/generated/app_localizations.dart';
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
      appBar: AppBar(title: Text(l10n.tracksTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(_create(context, ref)),
        icon: const Icon(Icons.add),
        label: Text(l10n.tracksNew),
      ),
      body: switch (tracks) {
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.all(16),
          children: [for (final track in value) _TrackTile(track: track)],
        ),
        AsyncError() => Center(child: Text(l10n.errorGeneric)),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
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
