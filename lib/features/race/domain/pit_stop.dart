import 'package:meta/meta.dart';

/// One completed pass through the pit lane, from the entry line to the
/// exit line.
@immutable
class PitStop {
  /// Creates a pit stop record.
  const PitStop({
    required this.number,
    required this.entryMicros,
    required this.exitMicros,
    required this.maxSpeedKmh,
    required this.stopped,
  });

  /// Decodes [toJson] output; returns null when malformed.
  static PitStop? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final number = json['n'];
    final entry = json['in'];
    final exit = json['out'];
    final max = json['max'];
    final stopped = json['stopped'];
    if (number is! int || entry is! int || exit is! int || max is! num) {
      return null;
    }
    return PitStop(
      number: number,
      entryMicros: entry,
      exitMicros: exit,
      maxSpeedKmh: max.toDouble(),
      stopped: stopped == true,
    );
  }

  /// 1-based pit stop number in the session.
  final int number;

  /// Crossing time of the pit entry line (GPS time, µs).
  final int entryMicros;

  /// Crossing time of the pit exit line (GPS time, µs).
  final int exitMicros;

  /// Highest speed measured in the pit lane.
  final double maxSpeedKmh;

  /// Whether the car came to a stop (a drive-through does not).
  final bool stopped;

  /// Total time in the pit lane.
  int get durationMicros => exitMicros - entryMicros;

  /// JSON for storage.
  Map<String, Object?> toJson() => {
    'n': number,
    'in': entryMicros,
    'out': exitMicros,
    'max': maxSpeedKmh,
    'stopped': stopped,
  };
}
