import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lap_timer/app/infrastructure_providers.dart';
import 'package:lap_timer/features/brake_coach/domain/brake_alert.dart';
import 'package:lap_timer/features/brake_coach/domain/brake_profile.dart';
import 'package:lap_timer/features/sessions/domain/session.dart';
import 'package:lap_timer/features/tracks/domain/track.dart';
import 'package:lap_timer/features/tracks/presentation/text_prompt.dart';
import 'package:lap_timer/features/tracks/presentation/track_map_view.dart';
import 'package:lap_timer/l10n/generated/app_localizations.dart';
import 'package:lap_timer/theme/app_colors.dart';
import 'package:material_ui/material_ui.dart';

/// Review and adjust the brake points of a session, corner by corner, then
/// save them as a named profile (mockup 8).
///
/// Edits change the session's draft only; nothing becomes a reusable
/// profile until "Save profile" is tapped.
class CornersScreen extends ConsumerStatefulWidget {
  /// Edits the brake points of the session with [sessionId].
  const CornersScreen({required this.sessionId, super.key});

  /// Session whose brake points are shown.
  final String sessionId;

  @override
  ConsumerState<CornersScreen> createState() => _CornersScreenState();
}

class _CornersScreenState extends ConsumerState<CornersScreen> {
  int _selected = 0;
  final Set<int> _dismissed = {};

  Session? get _session {
    final sessions = ref.watch(sessionsProvider).value ?? const <Session>[];
    return sessions.where((s) => s.id == widget.sessionId).firstOrNull;
  }

  Future<void> _updateCorner(
    Session session,
    int index,
    CornerBrakePoint Function(CornerBrakePoint) change,
  ) async {
    final profile = session.brakeProfile;
    if (profile == null) return;
    final corners = List.generate(
      profile.corners.length,
      (i) => i == index ? change(profile.corners[i]) : profile.corners[i],
    );
    await ref
        .read(sessionRepositoryProvider)
        .save(session.withBrakeProfile(profile.copyWith(corners: corners)));
  }

  Future<void> _saveProfile(Session session) async {
    final l10n = AppLocalizations.of(context);
    final profile = session.brakeProfile;
    if (profile == null) return;
    final name = await promptForText(
      context,
      title: l10n.cornersSaveProfile,
      initial: profile.name,
    );
    if (name == null || name.trim().isEmpty) return;
    final saved = profile.copyWith(name: name.trim());
    await ref.read(brakeProfileRepositoryProvider).save(saved);
    await ref
        .read(sessionRepositoryProvider)
        .save(session.withBrakeProfile(saved));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.cornersSaved(saved.name))));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = _session;
    final profile = session?.brakeProfile;
    if (session == null || profile == null || profile.corners.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.cornersTitle)),
        body: Center(child: Text(l10n.cornersNone)),
      );
    }
    final selected = _selected.clamp(0, profile.corners.length - 1);
    final tracks = ref.watch(tracksProvider).value ?? const <Track>[];
    final track = tracks.where((t) => t.id == session.trackId).firstOrNull;
    final suggestions = {
      for (final s in calibrationSuggestions(session.brakeMisses))
        s.cornerIndex: s,
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.cornersTitle),
        actions: [
          TextButton(
            onPressed: () => unawaited(_saveProfile(session)),
            child: Text(l10n.cornersSaveProfile),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(profile.name, style: Theme.of(context).textTheme.titleMedium),
          if (track != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 240,
                child: TrackMapView(
                  track: track,
                  pathLatLng: profile.pathLatLng,
                  pointMarkers: [
                    for (final (i, c) in profile.corners.indexed)
                      (c.latitude, c.longitude, '${i + 1}', i == selected),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          for (final (i, corner) in profile.corners.indexed)
            _CornerCard(
              index: i,
              corner: corner,
              selected: i == selected,
              suggestion: _dismissed.contains(i) ? null : suggestions[i],
              onSelect: () => setState(() => _selected = i),
              onChange: (change) =>
                  unawaited(_updateCorner(session, i, change)),
              onDismissSuggestion: () => setState(() => _dismissed.add(i)),
            ),
        ],
      ),
    );
  }
}

class _CornerCard extends StatelessWidget {
  const _CornerCard({
    required this.index,
    required this.corner,
    required this.selected,
    required this.suggestion,
    required this.onSelect,
    required this.onChange,
    required this.onDismissSuggestion,
  });

  final int index;
  final CornerBrakePoint corner;
  final bool selected;
  final CalibrationSuggestion? suggestion;
  final VoidCallback onSelect;
  final void Function(CornerBrakePoint Function(CornerBrakePoint)) onChange;
  final VoidCallback onDismissSuggestion;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final offset = corner.offsetMetres;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? colors.warning : colors.outline,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.cornersTurn(index + 1),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: corner.locked
                        ? l10n.cornersUnlock
                        : l10n.cornersLock,
                    icon: Icon(corner.locked ? Icons.lock : Icons.lock_open),
                    onPressed: () =>
                        onChange((c) => c.copyWith(locked: !c.locked)),
                  ),
                ],
              ),
              Text(
                l10n.cornersInfo(
                  corner.brakeDistanceMetres.round(),
                  corner.sourceLapNumber ?? 0,
                ),
                style: TextStyle(color: colors.textMuted),
              ),
              if (suggestion case final s?)
                _SuggestionBanner(
                  suggestion: s,
                  onApply: () => onChange(
                    (c) => c.copyWith(
                      offsetMetres:
                          c.offsetMetres + s.suggestedOffsetChangeMetres,
                    ),
                  ),
                  onDismiss: onDismissSuggestion,
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => onChange(
                        (c) => c.copyWith(offsetMetres: c.offsetMetres - 5),
                      ),
                      child: Text(l10n.cornersEarlier),
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text(
                      '${offset >= 0 ? '+' : '−'}'
                      '${offset.abs().toStringAsFixed(0)} m',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => onChange(
                        (c) => c.copyWith(offsetMetres: c.offsetMetres + 5),
                      ),
                      child: Text(l10n.cornersLater),
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: offset == 0
                    ? null
                    : () => onChange((c) => c.copyWith(offsetMetres: 0)),
                child: Text(l10n.cornersReset),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionBanner extends StatelessWidget {
  const _SuggestionBanner({
    required this.suggestion,
    required this.onApply,
    required this.onDismiss,
  });

  final CalibrationSuggestion suggestion;
  final VoidCallback onApply;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final miss = suggestion.typicalMissMetres;
    final change = suggestion.suggestedOffsetChangeMetres;
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
            miss > 0
                ? l10n.cornersSuggestLate(
                    miss.round(),
                    suggestion.lapsAgreeing,
                    suggestion.lapsObserved,
                    change.abs().round(),
                  )
                : l10n.cornersSuggestEarly(
                    miss.abs().round(),
                    suggestion.lapsAgreeing,
                    suggestion.lapsObserved,
                    change.abs().round(),
                  ),
          ),
          Row(
            children: [
              FilledButton(onPressed: onApply, child: Text(l10n.cornersApply)),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onDismiss,
                child: Text(l10n.cornersDismiss),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
