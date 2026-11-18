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
  };
}
