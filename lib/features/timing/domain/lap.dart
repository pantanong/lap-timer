import 'package:meta/meta.dart';

/// One timed lap: start and end time plus the time of each sector.
///
/// All times are microseconds. A sector time is null when its split line
/// was missed (e.g. a GPS dropout), so the lap still counts but that sector
/// is unknown.
@immutable
class Lap {
  /// Creates a lap.
  const Lap({
    required this.number,
    required this.startMicros,
    required this.endMicros,
    required this.sectorMicros,
  });

  /// Decodes [toJson] output; returns null when malformed.
  static Lap? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final number = json['n'];
    final start = json['start'];
    final end = json['end'];
    final sectors = json['sectors'];
    if (number is! int || start is! int || end is! int) return null;
    if (sectors is! List<Object?>) return null;
    return Lap(
      number: number,
      startMicros: start,
      endMicros: end,
      sectorMicros: sectors.map((s) => s is int ? s : null).toList(),
    );
  }

  /// 1-based lap number within the session.
  final int number;

  /// Crossing time of the start/finish line that began the lap.
  final int startMicros;

  /// Crossing time of the start/finish line that ended the lap.
  final int endMicros;

  /// Time of each sector in order; null for a missed split.
  final List<int?> sectorMicros;

  /// Lap time in microseconds.
  int get timeMicros => endMicros - startMicros;

  /// Whether every sector time is known.
  bool get hasAllSectors => sectorMicros.every((s) => s != null);

  /// JSON for storage.
  Map<String, Object?> toJson() => {
    'n': number,
    'start': startMicros,
    'end': endMicros,
    'sectors': sectorMicros,
  };

  @override
  bool operator ==(Object other) =>
      other is Lap &&
      other.number == number &&
      other.startMicros == startMicros &&
      other.endMicros == endMicros &&
      _listEquals(other.sectorMicros, sectorMicros);

  @override
  int get hashCode =>
      Object.hash(number, startMicros, endMicros, Object.hashAll(sectorMicros));

  static bool _listEquals(List<int?> a, List<int?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
