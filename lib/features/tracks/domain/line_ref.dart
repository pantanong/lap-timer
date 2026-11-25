import 'package:lap_timer/features/tracks/domain/gate_line.dart';
import 'package:lap_timer/features/tracks/domain/track.dart';
import 'package:meta/meta.dart';

/// Which kind of single (non-split) line of a track.
enum TrackLine {
  /// Start/finish.
  startFinish,

  /// Pit lane entry.
  pitEntry,

  /// Pit lane exit.
  pitExit,
}

/// Points at one line of a track: a single line, or one split of a sector
/// layout. Lets one editor screen work on any line.
@immutable
sealed class LineRef {
  const LineRef();

  /// Encodes the reference for a route query (`sf`, `pitIn`, `pitOut`, or
  /// `split:<layoutId>:<index>`).
  String encode();

  /// Decodes [encode] output; null when malformed.
  static LineRef? tryDecode(String? text) {
    switch (text) {
      case 'sf':
        return const SingleLineRef(TrackLine.startFinish);
      case 'pitIn':
        return const SingleLineRef(TrackLine.pitEntry);
      case 'pitOut':
        return const SingleLineRef(TrackLine.pitExit);
    }
    if (text == null || !text.startsWith('split:')) return null;
    final rest = text.substring('split:'.length);
    final colon = rest.lastIndexOf(':');
    if (colon <= 0) return null;
    final index = int.tryParse(rest.substring(colon + 1));
    if (index == null || index < 0) return null;
    return SplitLineRef(rest.substring(0, colon), index);
  }
}

/// Start/finish, pit entry or pit exit.
final class SingleLineRef extends LineRef {
  /// Points at [line].
  const SingleLineRef(this.line);

  /// The line.
  final TrackLine line;

  @override
  String encode() => switch (line) {
    TrackLine.startFinish => 'sf',
    TrackLine.pitEntry => 'pitIn',
    TrackLine.pitExit => 'pitOut',
  };

  @override
  bool operator ==(Object other) =>
      other is SingleLineRef && other.line == line;

  @override
  int get hashCode => line.hashCode;
}

/// Split number [index] (0-based, driving order) of layout [layoutId].
final class SplitLineRef extends LineRef {
  /// Points at one split.
  const SplitLineRef(this.layoutId, this.index);

  /// The layout.
  final String layoutId;

  /// 0-based position in the layout's splits.
  final int index;

  @override
  String encode() => 'split:$layoutId:$index';

  @override
  bool operator ==(Object other) =>
      other is SplitLineRef &&
      other.layoutId == layoutId &&
      other.index == index;

  @override
  int get hashCode => Object.hash(layoutId, index);
}

/// Reading and replacing a line by [LineRef].
extension TrackLineAccess on Track {
  /// The line [ref] points at, or null when not set / not found.
  GateLine? lineAt(LineRef ref) => switch (ref) {
    SingleLineRef(line: TrackLine.startFinish) => startFinish,
    SingleLineRef(line: TrackLine.pitEntry) => pitEntry,
    SingleLineRef(line: TrackLine.pitExit) => pitExit,
    SplitLineRef(:final layoutId, :final index) => () {
      for (final l in sectorLayouts) {
        if (l.id == layoutId) {
          return index < l.splits.length ? l.splits[index] : null;
        }
      }
      return null;
    }(),
  };

  /// A copy with the line at [ref] replaced by [gate]. A split index past
  /// the end is ignored (use "add split" for new splits).
  Track withLineAt(LineRef ref, GateLine gate) => switch (ref) {
    SingleLineRef(line: TrackLine.startFinish) => copyWith(startFinish: gate),
    SingleLineRef(line: TrackLine.pitEntry) => copyWith(pitEntry: gate),
    SingleLineRef(line: TrackLine.pitExit) => copyWith(pitExit: gate),
    SplitLineRef(:final layoutId, :final index) => copyWith(
      sectorLayouts: [
        for (final l in sectorLayouts)
          if (l.id == layoutId && index < l.splits.length)
            l.copyWith(splits: [...l.splits]..[index] = gate)
          else
            l,
      ],
    ),
  };
}
