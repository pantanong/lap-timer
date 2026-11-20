import 'package:lap_timer/core/geo/local_point.dart';
import 'package:lap_timer/features/tracks/domain/gate_line.dart';
import 'package:lap_timer/features/tracks/domain/track.dart';
import 'package:meta/meta.dart';

/// Which timing line of a track, for messages about it.
enum LineKind {
  /// Start/finish.
  startFinish,

  /// Pit entry.
  pitEntry,

  /// Pit exit.
  pitExit,

  /// A sector split.
  split,
}

/// A named line of a track.
@immutable
class NamedLine {
  /// Creates a named line.
  const NamedLine(this.kind, this.line, {this.layoutName, this.splitIndex});

  /// Kind of line.
  final LineKind kind;

  /// The line.
  final GateLine line;

  /// For splits: the sector layout it belongs to.
  final String? layoutName;

  /// For splits: 0-based index in its layout.
  final int? splitIndex;
}

/// Two lines placed suspiciously close to each other.
@immutable
class CloseLines {
  /// Creates the warning.
  const CloseLines(this.a, this.b, this.distanceMetres);

  /// First line.
  final NamedLine a;

  /// Second line.
  final NamedLine b;

  /// Distance between their centres.
  final double distanceMetres;
}

/// Lines closer than [minimumMetres] to each other. Such lines usually mean
/// a mistake (e.g. all lines set while standing in the same place): the
/// pit lane would then start at every start/finish crossing.
///
/// Splits of different sector layouts are never compared with each other
/// (two layouts often share the same split).
List<CloseLines> findCloseLines(Track track, {double minimumMetres = 30}) {
  final lines = <NamedLine>[
    if (track.startFinish case final l?) NamedLine(LineKind.startFinish, l),
    if (track.pitEntry case final l?) NamedLine(LineKind.pitEntry, l),
    if (track.pitExit case final l?) NamedLine(LineKind.pitExit, l),
    for (final layout in track.sectorLayouts)
      for (final (i, l) in layout.splits.indexed)
        NamedLine(LineKind.split, l, layoutName: layout.name, splitIndex: i),
  ];
  if (lines.isEmpty) return const [];
  final origin = lines.first.line;
  final projection = LocalProjection(
    originLatitude: origin.latitude,
    originLongitude: origin.longitude,
  );
  LocalPoint at(GateLine l) => projection.toLocal(l.latitude, l.longitude);
  final result = <CloseLines>[];
  for (var i = 0; i < lines.length; i++) {
    for (var j = i + 1; j < lines.length; j++) {
      final a = lines[i];
      final b = lines[j];
      final differentLayouts =
          a.kind == LineKind.split &&
          b.kind == LineKind.split &&
          a.layoutName != b.layoutName;
      if (differentLayouts) continue;
      final d = at(a.line).distanceTo(at(b.line));
      if (d < minimumMetres) result.add(CloseLines(a, b, d));
    }
  }
  return result;
}
