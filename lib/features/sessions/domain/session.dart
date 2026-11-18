import 'package:lap_timer/features/brake_coach/domain/brake_profile.dart';
import 'package:lap_timer/features/race/domain/pit_stop.dart';
import 'package:lap_timer/features/race/domain/stint.dart';
import 'package:lap_timer/features/timing/domain/lap.dart';
import 'package:meta/meta.dart';

/// Kind of vehicle; some features depend on it (e.g. the brake coach is
/// never available for bicycles).
enum VehicleType {
  /// Car.
  car,

  /// Go-kart.
  kart,

  /// Motorcycle.
  motorcycle,

  /// Bicycle (lap timing only).
  bicycle,
}

/// A finished (or in-progress) timing session on one track.
@immutable
class Session {
  /// Creates a session record.
  const Session({
    required this.id,
    required this.trackId,
    required this.trackName,
    required this.sectorLayoutName,
    required this.sectorCount,
    required this.vehicleType,
    required this.startedAt,
    required this.laps,
    this.gpsLogFileName,
    this.raceRulesName,
    this.stints = const [],
    this.pitStops = const [],
    this.brakeProfile,
    this.brakeMisses = const {},
  });

  /// Decodes [toJson] output; returns null when malformed.
  static Session? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final id = json['id'];
    final trackId = json['trackId'];
    final trackName = json['trackName'];
    final layout = json['sectorLayoutName'];
    final sectorCount = json['sectorCount'];
    final vehicle = json['vehicleType'];
    final started = json['startedAt'];
    final rawLaps = json['laps'];
    if (id is! String ||
        trackId is! String ||
        trackName is! String ||
        layout is! String ||
        sectorCount is! int ||
        vehicle is! String ||
        started is! String ||
        rawLaps is! List<Object?>) {
      return null;
    }
    final startedAt = DateTime.tryParse(started);
    if (startedAt == null) return null;
    final log = json['gpsLog'];
    final rules = json['rules'];
    final rawStints = json['stints'];
    final rawStops = json['pitStops'];
    final rawMisses = json['brakeMisses'];
    return Session(
      id: id,
      trackId: trackId,
      trackName: trackName,
      sectorLayoutName: layout,
      sectorCount: sectorCount,
      vehicleType: VehicleType.values.asNameMap()[vehicle] ?? VehicleType.car,
      startedAt: startedAt,
      laps: [for (final raw in rawLaps) ?Lap.tryFromJson(raw)],
      gpsLogFileName: log is String ? log : null,
      raceRulesName: rules is String ? rules : null,
      stints: [
        if (rawStints is List<Object?>)
          for (final raw in rawStints) ?Stint.tryFromJson(raw),
      ],
      pitStops: [
        if (rawStops is List<Object?>)
          for (final raw in rawStops) ?PitStop.tryFromJson(raw),
      ],
      brakeProfile: BrakeProfile.tryFromJson(json['brakeProfile']),
      brakeMisses: _decodeMisses(rawMisses),
    );
  }

  /// Stable identifier (also the file name).
  final String id;

  /// Track driven.
  final String trackId;

  /// Track name at the time (kept even if the track is renamed later).
  final String trackName;

  /// Sector layout used, e.g. "Buriram (3 Sectors)".
  final String sectorLayoutName;

  /// Sectors per lap in [laps].
  final int sectorCount;

  /// Vehicle kind.
  final VehicleType vehicleType;

  /// When the session started.
  final DateTime startedAt;

  /// Completed laps in order.
  final List<Lap> laps;

  /// Raw GPS log recorded during the session, for replay.
  final String? gpsLogFileName;

  /// Name of the race rules used, if any.
  final String? raceRulesName;

  /// Who drove when.
  final List<Stint> stints;

  /// Pit lane passes, in order.
  final List<PitStop> pitStops;

  /// Brake points at the end of the session (learned or from a saved
  /// profile, with any edits), for the Corners screen. Null if the brake
  /// coach was off or never finished learning.
  final BrakeProfile? brakeProfile;

  /// How far off each corner's brake point the driver braked, per lap
  /// (metres, positive = later), for calibration suggestions.
  final Map<int, List<double>> brakeMisses;

  /// Whether [lap] includes a pass through the pit lane (in-lap/out-lap).
  /// Such laps are kept but never count as best lap.
  bool isPitLap(Lap lap) => lapIncludesPitStop(lap, pitStops);

  /// Laps without a pit stop, used for best lap / best sectors.
  List<Lap> get racingLaps => [
    for (final lap in laps)
      if (!isPitLap(lap)) lap,
  ];

  /// The stint [lap] belongs to (by its start time), if stints are known.
  Stint? stintOf(Lap lap) {
    Stint? result;
    for (final s in stints) {
      if (s.startMicros <= lap.startMicros) result = s;
    }
    return result ?? (stints.isEmpty ? null : stints.first);
  }

  /// Returns a copy with the timing data replaced.
  Session withProgress({
    required List<Lap> laps,
    required List<Stint> stints,
    required List<PitStop> pitStops,
    BrakeProfile? brakeProfile,
    Map<int, List<double>>? brakeMisses,
  }) => Session(
    id: id,
    trackId: trackId,
    trackName: trackName,
    sectorLayoutName: sectorLayoutName,
    sectorCount: sectorCount,
    vehicleType: vehicleType,
    startedAt: startedAt,
    laps: laps,
    gpsLogFileName: gpsLogFileName,
    raceRulesName: raceRulesName,
    stints: stints,
    pitStops: pitStops,
    brakeProfile: brakeProfile ?? this.brakeProfile,
    brakeMisses: brakeMisses ?? this.brakeMisses,
  );

  /// Returns a copy with the brake profile replaced (Corners screen edits).
  Session withBrakeProfile(BrakeProfile profile) => withProgress(
    laps: laps,
    stints: stints,
    pitStops: pitStops,
    brakeProfile: profile,
  );

  /// Returns a copy with [laps] replaced.
  Session withLaps(List<Lap> laps) => Session(
    id: id,
    trackId: trackId,
    trackName: trackName,
    sectorLayoutName: sectorLayoutName,
    sectorCount: sectorCount,
    vehicleType: vehicleType,
    startedAt: startedAt,
    laps: laps,
    gpsLogFileName: gpsLogFileName,
    raceRulesName: raceRulesName,
    stints: stints,
    pitStops: pitStops,
    brakeProfile: brakeProfile,
    brakeMisses: brakeMisses,
  );

  /// JSON for storage.
  Map<String, Object?> toJson() => {
    'id': id,
    'trackId': trackId,
    'trackName': trackName,
    'sectorLayoutName': sectorLayoutName,
    'sectorCount': sectorCount,
    'vehicleType': vehicleType.name,
    'startedAt': startedAt.toIso8601String(),
    'laps': [for (final lap in laps) lap.toJson()],
    'gpsLog': ?gpsLogFileName,
    'rules': ?raceRulesName,
    'stints': [for (final st in stints) st.toJson()],
    'pitStops': [for (final p in pitStops) p.toJson()],
    if (brakeProfile case final profile?) 'brakeProfile': profile.toJson(),
    'brakeMisses': {for (final e in brakeMisses.entries) '${e.key}': e.value},
  };

  static Map<int, List<double>> _decodeMisses(Object? json) {
    if (json is! Map<String, Object?>) return const {};
    final result = <int, List<double>>{};
    for (final MapEntry(:key, :value) in json.entries) {
      final corner = int.tryParse(key);
      if (corner == null || value is! List<Object?>) continue;
      result[corner] = [
        for (final v in value)
          if (v is num) v.toDouble(),
      ];
    }
    return result;
  }
}

/// Whether [lap] overlaps any of [pitStops] in time.
bool lapIncludesPitStop(Lap lap, List<PitStop> pitStops) => pitStops.any(
  (p) => lap.startMicros < p.exitMicros && lap.endMicros > p.entryMicros,
);
