import 'dart:math' as math;

import 'package:lap_timer/features/gps/domain/simulated_track.dart';
import 'package:lap_timer/features/tracks/domain/gate_line.dart';
import 'package:lap_timer/features/tracks/domain/track.dart';

/// Id of the built-in track matching the GPS Simulator.
const String simulatorTrackId = 'simulator-circuit';

/// A ready-made track whose lines match the simulator's virtual circuit,
/// so the whole app can be tried at a desk with Simulator as GPS source.
Track simulatorTrackPreset([SimulatedTrack? simulated]) {
  final sim = simulated ?? SimulatedTrack();
  final length = sim.lapLengthMetres;
  return Track(
    id: simulatorTrackId,
    name: 'Simulator Circuit',
    startFinish: simulatorGateAt(sim, 0),
    defaultSectorLayoutId: 'sim-3',
    sectorLayouts: [
      SectorLayout(
        id: 'sim-3',
        name: 'Simulator (3 Sectors)',
        splits: [
          simulatorGateAt(sim, length / 3),
          simulatorGateAt(sim, 2 * length / 3),
        ],
      ),
      SectorLayout(
        id: 'sim-6',
        name: 'Simulator (6 Sectors)',
        splits: [
          for (var i = 1; i < 6; i++) simulatorGateAt(sim, i * length / 6),
        ],
      ),
    ],
    // Pit lane beside the start/finish straight (10 m to the right of the
    // racing line); short lines so normal laps never trigger pit mode.
    pitEntry: simulatorGateAt(
      sim,
      length - 120,
      offsetMetres: SimulatedTrack.pitLaneOffsetMetres,
      widthMetres: 8,
    ),
    pitExit: simulatorGateAt(
      sim,
      120,
      offsetMetres: SimulatedTrack.pitLaneOffsetMetres,
      widthMetres: 8,
    ),
  );
}

/// A gate across the simulated racing line at [distance] metres, optionally
/// moved [offsetMetres] to the right (the pit lane).
GateLine simulatorGateAt(
  SimulatedTrack sim,
  double distance, {
  double offsetMetres = 0,
  double widthMetres = 24,
}) {
  final p = sim.pointBeside(distance, offsetMetres);
  final ahead = sim.pointAt(distance + 1) - sim.pointAt(distance);
  final (lat, lon) = sim.projection.toLatLng(p);
  final bearing = (math.atan2(ahead.x, ahead.y) * 180 / math.pi + 360) % 360;
  return GateLine(
    latitude: lat,
    longitude: lon,
    travelBearingDegrees: bearing,
    widthMetres: widthMetres,
  );
}
