import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lap_timer/app/routes.dart';
import 'package:lap_timer/features/tracks/data/track_editing.dart';
import 'package:lap_timer/features/tracks/domain/line_ref.dart';
import 'package:lap_timer/features/tracks/domain/track.dart';
import 'package:lap_timer/features/tracks/presentation/position_capture_notifier.dart';
import 'package:lap_timer/features/tracks/presentation/text_prompt.dart';
import 'package:lap_timer/l10n/generated/app_localizations.dart';
import 'package:lap_timer/theme/app_colors.dart';
import 'package:material_ui/material_ui.dart';

/// One sector layout of a track: add splits in driving order with
/// "Add split here", undo the last one, rename, duplicate, make default.
class SectorLayoutCard extends ConsumerWidget {
  /// Shows [layout] of [track].
  const SectorLayoutCard({
    required this.track,
    required this.layout,
    super.key,
  });

  /// The track.
  final Track track;

  /// The layout shown.
  final SectorLayout layout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final editing = ref.read(trackEditingProvider);
    final isDefault = track.defaultSectorLayout?.id == layout.id;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    layout.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.trackMakeDefault,
                  icon: Icon(
                    isDefault ? Icons.star : Icons.star_border,
                    color: isDefault ? colors.warning : null,
                  ),
                  onPressed: () =>
                      unawaited(editing.setDefaultLayout(track.id, layout.id)),
                ),
                _LayoutMenu(track: track, layout: layout),
              ],
            ),
            Text(
              l10n.trackLayoutSummary(layout.sectorCount, layout.splits.length),
            ),
            if (layout.splits.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(l10n.trackSplitsTapToAdjust),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (var i = 0; i < layout.splits.length; i++)
                    ActionChip(
                      avatar: const Icon(Icons.tune, size: 18),
                      label: Text('S${i + 1}|${i + 2}'),
                      onPressed: () => context.push(
                        AppRoutes.trackLine(
                          track.id,
                          SplitLineRef(layout.id, i),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: () {
                    final gate = ref
                        .read(positionCaptureProvider.notifier)
                        .capture();
                    if (gate == null) return;
                    unawaited(editing.addSplit(track.id, layout.id, gate));
                  },
                  icon: const Icon(Icons.add_location_alt),
                  label: Text(l10n.trackAddSplitHere),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: layout.splits.isEmpty
                      ? null
                      : () => unawaited(
                          editing.removeLastSplit(track.id, layout.id),
                        ),
                  child: Text(l10n.trackUndoSplit),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _LayoutAction { rename, duplicate, delete }

class _LayoutMenu extends ConsumerWidget {
  const _LayoutMenu({required this.track, required this.layout});

  final Track track;
  final SectorLayout layout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<_LayoutAction>(
      onSelected: (action) => unawaited(_run(context, ref, action)),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _LayoutAction.rename,
          child: Text(l10n.actionRename),
        ),
        PopupMenuItem(
          value: _LayoutAction.duplicate,
          child: Text(l10n.actionDuplicate),
        ),
        PopupMenuItem(
          value: _LayoutAction.delete,
          child: Text(l10n.actionDelete),
        ),
      ],
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    _LayoutAction action,
  ) async {
    final l10n = AppLocalizations.of(context);
    final editing = ref.read(trackEditingProvider);
    switch (action) {
      case _LayoutAction.rename:
        final name = await promptForText(
          context,
          title: l10n.actionRename,
          initial: layout.name,
        );
        if (name != null && name.trim().isNotEmpty) {
          await editing.renameLayout(track.id, layout.id, name);
        }
      case _LayoutAction.duplicate:
        final name = await promptForText(
          context,
          title: l10n.actionDuplicate,
          initial: '${layout.name} (copy)',
        );
        if (name != null && name.trim().isNotEmpty) {
          await editing.duplicateLayout(track.id, layout.id, name);
        }
      case _LayoutAction.delete:
        if (await confirm(context, l10n.trackDeleteLayoutConfirm)) {
          await editing.deleteLayout(track.id, layout.id);
        }
    }
  }
}
