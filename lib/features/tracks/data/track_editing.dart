import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lap_timer/app/infrastructure_providers.dart';
import 'package:lap_timer/features/tracks/data/track_repository.dart';
import 'package:lap_timer/features/tracks/domain/gate_line.dart';
import 'package:lap_timer/features/tracks/domain/track.dart';

/// Which single line of a track is being set.
enum TrackLine {
  /// Start/finish.
  startFinish,

  /// Pit lane entry.
  pitEntry,

  /// Pit lane exit.
  pitExit,
}

/// Every edit the track editor can make. Each method loads the latest
/// track, applies one change and saves it through the repository (the
/// single write path).
class TrackEditing {
  /// Creates the editor actions.
  TrackEditing(this._repository, this._clock);

  final TrackRepository _repository;
  final Clock _clock;

  Future<void> _update(String trackId, Track Function(Track) change) async {
    final track = await _repository.byId(trackId);
    if (track == null) return;
    await _repository.save(change(track));
  }

  /// Renames the track.
  Future<void> rename(String trackId, String name) =>
      _update(trackId, (t) => t.copyWith(name: name.trim()));

  /// Sets one of the single lines.
  Future<void> setLine(String trackId, TrackLine line, GateLine gate) =>
      _update(
        trackId,
        (t) => switch (line) {
          TrackLine.startFinish => t.copyWith(startFinish: gate),
          TrackLine.pitEntry => t.copyWith(pitEntry: gate),
          TrackLine.pitExit => t.copyWith(pitExit: gate),
        },
      );

  /// Removes one of the single lines (e.g. pit lines on a practice track).
  Future<void> clearLine(String trackId, TrackLine line) => _update(
    trackId,
    (t) => Track(
      id: t.id,
      name: t.name,
      startFinish: line == TrackLine.startFinish ? null : t.startFinish,
      sectorLayouts: t.sectorLayouts,
      defaultSectorLayoutId: t.defaultSectorLayoutId,
      pitEntry: line == TrackLine.pitEntry ? null : t.pitEntry,
      pitExit: line == TrackLine.pitExit ? null : t.pitExit,
    ),
  );

  /// Adds an empty sector layout named [name].
  Future<void> addLayout(String trackId, String name) => _update(trackId, (t) {
    final layout = SectorLayout(
      id: 'layout-${_clock.now().microsecondsSinceEpoch}',
      name: name.trim(),
    );
    return t.copyWith(
      sectorLayouts: [...t.sectorLayouts, layout],
      defaultSectorLayoutId: t.defaultSectorLayoutId ?? layout.id,
    );
  });

  /// Copies a layout (e.g. "3 Sectors" → "5 Sectors" with extra splits).
  Future<void> duplicateLayout(String trackId, String layoutId, String name) =>
      _update(trackId, (t) {
        final source = t.sectorLayouts.where((l) => l.id == layoutId);
        if (source.isEmpty) return t;
        final copy = SectorLayout(
          id: 'layout-${_clock.now().microsecondsSinceEpoch}',
          name: name.trim(),
          splits: source.first.splits,
        );
        return t.copyWith(sectorLayouts: [...t.sectorLayouts, copy]);
      });

  /// Renames a layout.
  Future<void> renameLayout(String trackId, String layoutId, String name) =>
      _editLayout(trackId, layoutId, (l) => l.copyWith(name: name.trim()));

  /// Appends a split line at the end of a layout (driving order).
  Future<void> addSplit(String trackId, String layoutId, GateLine gate) =>
      _editLayout(
        trackId,
        layoutId,
        (l) => l.copyWith(splits: [...l.splits, gate]),
      );

  /// Removes the last split line of a layout.
  Future<void> removeLastSplit(String trackId, String layoutId) => _editLayout(
    trackId,
    layoutId,
    (l) => l.splits.isEmpty
        ? l
        : l.copyWith(splits: l.splits.sublist(0, l.splits.length - 1)),
  );

  /// Makes a layout the one preselected for new sessions.
  Future<void> setDefaultLayout(String trackId, String layoutId) =>
      _update(trackId, (t) => t.copyWith(defaultSectorLayoutId: layoutId));

  /// Deletes a layout.
  Future<void> deleteLayout(String trackId, String layoutId) => _update(
    trackId,
    (t) => t.copyWith(
      sectorLayouts: [
        for (final l in t.sectorLayouts)
          if (l.id != layoutId) l,
      ],
    ),
  );

  /// Deletes the whole track.
  Future<void> deleteTrack(String trackId) => _repository.delete(trackId);

  Future<void> _editLayout(
    String trackId,
    String layoutId,
    SectorLayout Function(SectorLayout) change,
  ) => _update(
    trackId,
    (t) => t.copyWith(
      sectorLayouts: t.sectorLayouts
          .map((l) => l.id == layoutId ? change(l) : l)
          .toList(),
    ),
  );
}

/// Track editing actions.
final Provider<TrackEditing> trackEditingProvider = Provider<TrackEditing>(
  (ref) => TrackEditing(
    ref.watch(trackRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
