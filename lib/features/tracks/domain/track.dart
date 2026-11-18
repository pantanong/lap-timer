import 'package:lap_timer/features/tracks/domain/gate_line.dart';
import 'package:meta/meta.dart';

/// A named set of sector lines for a track, e.g. "Buriram (3 Sectors)".
///
/// [splits] are the intermediate lines in driving order; the start/finish
/// line closes the last sector, so `n` splits give `n + 1` sectors.
@immutable
class SectorLayout {
  /// Creates a layout.
  const SectorLayout({
    required this.id,
    required this.name,
    this.splits = const [],
  });

  /// Decodes [toJson] output; returns null when malformed.
  static SectorLayout? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final id = json['id'];
    final name = json['name'];
    final rawSplits = json['splits'];
    if (id is! String || name is! String || rawSplits is! List<Object?>) {
      return null;
    }
    final splits = <GateLine>[];
    for (final raw in rawSplits) {
      final gate = GateLine.tryFromJson(raw);
      if (gate == null) return null;
      splits.add(gate);
    }
    return SectorLayout(id: id, name: name, splits: splits);
  }

  /// Stable identifier.
  final String id;

  /// User-visible name.
  final String name;

  /// Intermediate split lines in driving order.
  final List<GateLine> splits;

  /// Number of sectors in a lap.
  int get sectorCount => splits.length + 1;

  /// Returns a copy with some fields replaced.
  SectorLayout copyWith({String? name, List<GateLine>? splits}) => SectorLayout(
    id: id,
    name: name ?? this.name,
    splits: splits ?? this.splits,
  );

  /// JSON for storage.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'splits': [for (final s in splits) s.toJson()],
  };
}

/// A circuit (or any closed loop) the user times laps on.
@immutable
class Track {
  /// Creates a track.
  const Track({
    required this.id,
    required this.name,
    this.startFinish,
    this.sectorLayouts = const [],
    this.defaultSectorLayoutId,
    this.pitEntry,
    this.pitExit,
  });

  /// Decodes [toJson] output; returns null when malformed.
  static Track? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! String || name is! String) return null;
    final layouts = <SectorLayout>[];
    final rawLayouts = json['sectorLayouts'];
    if (rawLayouts is List<Object?>) {
      for (final raw in rawLayouts) {
        final layout = SectorLayout.tryFromJson(raw);
        if (layout != null) layouts.add(layout);
      }
    }
    final defaultId = json['defaultSectorLayoutId'];
    return Track(
      id: id,
      name: name,
      startFinish: GateLine.tryFromJson(json['startFinish']),
      sectorLayouts: layouts,
      defaultSectorLayoutId: defaultId is String ? defaultId : null,
      pitEntry: GateLine.tryFromJson(json['pitEntry']),
      pitExit: GateLine.tryFromJson(json['pitExit']),
    );
  }

  /// Stable identifier.
  final String id;

  /// User-visible name.
  final String name;

  /// The timing line; laps cannot be timed until it is set.
  final GateLine? startFinish;

  /// Saved sector layouts for this track.
  final List<SectorLayout> sectorLayouts;

  /// Layout preselected when starting a session.
  final String? defaultSectorLayoutId;

  /// Pit lane entry line (used by pit mode).
  final GateLine? pitEntry;

  /// Pit lane exit line (used by pit mode).
  final GateLine? pitExit;

  /// The default layout, or the first one, or null when there are none.
  SectorLayout? get defaultSectorLayout {
    for (final layout in sectorLayouts) {
      if (layout.id == defaultSectorLayoutId) return layout;
    }
    return sectorLayouts.isEmpty ? null : sectorLayouts.first;
  }

  /// Returns a copy with the given fields replaced.
  Track copyWith({
    String? name,
    GateLine? startFinish,
    List<SectorLayout>? sectorLayouts,
    String? defaultSectorLayoutId,
    GateLine? pitEntry,
    GateLine? pitExit,
  }) => Track(
    id: id,
    name: name ?? this.name,
    startFinish: startFinish ?? this.startFinish,
    sectorLayouts: sectorLayouts ?? this.sectorLayouts,
    defaultSectorLayoutId: defaultSectorLayoutId ?? this.defaultSectorLayoutId,
    pitEntry: pitEntry ?? this.pitEntry,
    pitExit: pitExit ?? this.pitExit,
  );

  /// JSON for storage.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (startFinish case final line?) 'startFinish': line.toJson(),
    'sectorLayouts': [for (final l in sectorLayouts) l.toJson()],
    'defaultSectorLayoutId': ?defaultSectorLayoutId,
    if (pitEntry case final line?) 'pitEntry': line.toJson(),
    if (pitExit case final line?) 'pitExit': line.toJson(),
  };
}
