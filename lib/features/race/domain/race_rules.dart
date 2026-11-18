import 'package:meta/meta.dart';

/// The rules of one race or championship that the app helps the driver
/// respect: pit lane speed limit, minimum time in the pit lane and the
/// number of mandatory stops.
///
/// Rules belong to the race, not to the track: the same circuit can host
/// races with different rules. The user picks a rule set when starting a
/// session.
@immutable
class RaceRules {
  /// Creates a rule set. Defaults match a typical club race.
  const RaceRules({
    required this.id,
    required this.name,
    this.pitSpeedLimitKmh = 60,
    this.pitTargetSpeedKmh = 55,
    this.minimumPitTime = const Duration(minutes: 1),
    this.pitTimeSafetyMargin = Duration.zero,
    this.pitResultHold = const Duration(seconds: 10),
    this.requiredPitStops = 1,
    this.resumeSpeedKmh = 20,
  });

  /// Decodes [toJson] output; returns null when malformed.
  static RaceRules? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! String || name is! String) return null;
    double number(String key, double fallback) => switch (json[key]) {
      final num n => n.toDouble(),
      _ => fallback,
    };
    Duration millis(String key, Duration fallback) => switch (json[key]) {
      final int ms => Duration(milliseconds: ms),
      _ => fallback,
    };
    const defaults = RaceRules(id: '', name: '');
    return RaceRules(
      id: id,
      name: name,
      pitSpeedLimitKmh: number('limitKmh', defaults.pitSpeedLimitKmh),
      pitTargetSpeedKmh: number('targetKmh', defaults.pitTargetSpeedKmh),
      minimumPitTime: millis('minPitMs', defaults.minimumPitTime),
      pitTimeSafetyMargin: millis('marginMs', defaults.pitTimeSafetyMargin),
      pitResultHold: millis('holdMs', defaults.pitResultHold),
      requiredPitStops: switch (json['stops']) {
        final int n => n,
        _ => defaults.requiredPitStops,
      },
      resumeSpeedKmh: number('resumeKmh', defaults.resumeSpeedKmh),
    );
  }

  /// Stable identifier.
  final String id;

  /// User-visible name, e.g. "Thailand Super Series".
  final String name;

  /// Maximum speed allowed in the pit lane.
  final double pitSpeedLimitKmh;

  /// Speed the driver aims for (below the limit, to leave a margin).
  final double pitTargetSpeedKmh;

  /// Minimum time from pit entry to pit exit, stop included.
  final Duration minimumPitTime;

  /// Extra time added to [minimumPitTime] for safety (timing differences
  /// between the app and the officials).
  final Duration pitTimeSafetyMargin;

  /// How long the pit result stays on screen after the pit exit.
  final Duration pitResultHold;

  /// Mandatory pit stops in the race.
  final int requiredPitStops;

  /// While stopped in the pit, the next driver's name is shown instead of
  /// the speed until the car is faster than this again.
  final double resumeSpeedKmh;

  /// The pit time the driver should reach: minimum + safety margin.
  Duration get targetPitTime => minimumPitTime + pitTimeSafetyMargin;

  /// Returns a copy with the given fields replaced.
  RaceRules copyWith({
    String? name,
    double? pitSpeedLimitKmh,
    double? pitTargetSpeedKmh,
    Duration? minimumPitTime,
    Duration? pitTimeSafetyMargin,
    Duration? pitResultHold,
    int? requiredPitStops,
    double? resumeSpeedKmh,
  }) => RaceRules(
    id: id,
    name: name ?? this.name,
    pitSpeedLimitKmh: pitSpeedLimitKmh ?? this.pitSpeedLimitKmh,
    pitTargetSpeedKmh: pitTargetSpeedKmh ?? this.pitTargetSpeedKmh,
    minimumPitTime: minimumPitTime ?? this.minimumPitTime,
    pitTimeSafetyMargin: pitTimeSafetyMargin ?? this.pitTimeSafetyMargin,
    pitResultHold: pitResultHold ?? this.pitResultHold,
    requiredPitStops: requiredPitStops ?? this.requiredPitStops,
    resumeSpeedKmh: resumeSpeedKmh ?? this.resumeSpeedKmh,
  );

  /// JSON for storage.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'limitKmh': pitSpeedLimitKmh,
    'targetKmh': pitTargetSpeedKmh,
    'minPitMs': minimumPitTime.inMilliseconds,
    'marginMs': pitTimeSafetyMargin.inMilliseconds,
    'holdMs': pitResultHold.inMilliseconds,
    'stops': requiredPitStops,
    'resumeKmh': resumeSpeedKmh,
  };
}
