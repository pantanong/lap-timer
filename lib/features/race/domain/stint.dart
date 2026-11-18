import 'package:meta/meta.dart';

/// A continuous period driven by one driver. "Nong(2)" is Nong's second
/// stint.
@immutable
class Stint {
  /// Creates a stint.
  const Stint({
    required this.driverName,
    required this.number,
    required this.startMicros,
  });

  /// Decodes [toJson] output; returns null when malformed.
  static Stint? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final name = json['driver'];
    final number = json['n'];
    final start = json['start'];
    if (name is! String || number is! int || start is! int) return null;
    return Stint(driverName: name, number: number, startMicros: start);
  }

  /// Who drives.
  final String driverName;

  /// This driver's stint number (1, 2, …).
  final int number;

  /// When the stint started (GPS time, µs); 0 for the first stint.
  final int startMicros;

  /// Display label, e.g. "Nong(2)".
  String get label => '$driverName($number)';

  /// JSON for storage.
  Map<String, Object?> toJson() => {
    'driver': driverName,
    'n': number,
    'start': startMicros,
  };

  @override
  bool operator ==(Object other) =>
      other is Stint &&
      other.driverName == driverName &&
      other.number == number &&
      other.startMicros == startMicros;

  @override
  int get hashCode => Object.hash(driverName, number, startMicros);
}

/// Decides who drives next.
///
/// The roster is the ordered list of drivers. At every pit stop where the
/// car stops, the next driver in the roster takes over — unless "Same
/// driver" was pressed, in which case the current driver continues with a
/// new stint number. With a single driver the roster simply repeats:
/// Nong(1) → Nong(2) → Nong(3).
@immutable
class StintPlan {
  /// Starts a plan with [roster] (at least one name).
  StintPlan.start(List<String> roster)
    : roster = List.unmodifiable(roster.isEmpty ? const ['Driver'] : roster),
      stints = List.unmodifiable([
        Stint(
          driverName: roster.isEmpty ? 'Driver' : roster.first,
          number: 1,
          startMicros: 0,
        ),
      ]),
      _rosterIndex = 0;

  const StintPlan._(this.roster, this.stints, this._rosterIndex);

  /// Drivers in driving order.
  final List<String> roster;

  /// Stints so far, oldest first.
  final List<Stint> stints;

  final int _rosterIndex;

  /// The stint being driven.
  Stint get current => stints.last;

  /// The stint that starts at the next driver change.
  Stint nextStint({required bool sameDriver, int startMicros = 0}) {
    final index = sameDriver
        ? _rosterIndex
        : (_rosterIndex + 1) % roster.length;
    final name = roster[index];
    final previous = stints.where((s) => s.driverName == name).length;
    return Stint(
      driverName: name,
      number: previous + 1,
      startMicros: startMicros,
    );
  }

  /// Starts the next stint at [atMicros].
  StintPlan advance({required bool sameDriver, required int atMicros}) {
    final next = nextStint(sameDriver: sameDriver, startMicros: atMicros);
    final index = sameDriver
        ? _rosterIndex
        : (_rosterIndex + 1) % roster.length;
    return StintPlan._(roster, List.unmodifiable([...stints, next]), index);
  }

  /// The stint a moment in time belongs to.
  Stint stintAt(int micros) {
    var result = stints.first;
    for (final s in stints) {
      if (s.startMicros <= micros) result = s;
    }
    return result;
  }
}
