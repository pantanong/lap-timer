import 'package:lap_timer/features/timing/domain/lap.dart';

/// What each sector of the current lap is compared against.
enum SectorCompareMode {
  /// The sectors of the fastest complete lap: answers "am I on course for a
  /// new best lap?". Default.
  bestLap,

  /// The fastest time ever driven in each sector, from any lap: answers
  /// "can I still go faster in this part of the track?".
  bestSector,
}

/// Session-wide references derived from the completed laps. Computed on
/// demand, never stored, so it can never drift out of sync with the laps.
class LapReferences {
  /// Derives the references from [laps] with [sectorCount] sectors each.
  factory LapReferences.from(List<Lap> laps, {required int sectorCount}) {
    Lap? bestLap;
    final bestSectors = List<int?>.filled(sectorCount, null);
    for (final lap in laps) {
      if (bestLap == null || lap.timeMicros < bestLap.timeMicros) {
        bestLap = lap;
      }
      for (var i = 0; i < sectorCount && i < lap.sectorMicros.length; i++) {
        final t = lap.sectorMicros[i];
        final best = bestSectors[i];
        if (t != null && (best == null || t < best)) bestSectors[i] = t;
      }
    }
    return LapReferences._(bestLap, List.unmodifiable(bestSectors));
  }

  LapReferences._(this.bestLap, this.bestSectorMicros);

  /// Fastest lap so far, or null before the first lap is completed.
  final Lap? bestLap;

  /// Fastest time in each sector over all laps (null if never timed).
  final List<int?> bestSectorMicros;

  /// Sum of [bestSectorMicros] — the "optimal" or theoretical best lap.
  /// Null until every sector has been timed at least once.
  int? get optimalLapMicros {
    var total = 0;
    for (final t in bestSectorMicros) {
      if (t == null) return null;
      total += t;
    }
    return bestSectorMicros.isEmpty ? null : total;
  }

  /// The reference time of every sector for [mode].
  List<int?> referenceSectors(SectorCompareMode mode) => switch (mode) {
    SectorCompareMode.bestLap =>
      bestLap?.sectorMicros ?? List.filled(bestSectorMicros.length, null),
    SectorCompareMode.bestSector => bestSectorMicros,
  };

  /// Gap of a sector time to its reference: negative = faster (green),
  /// positive = slower (red). Null when there is nothing to compare with.
  int? sectorDeltaMicros(
    int sectorIndex,
    int sectorMicros,
    SectorCompareMode mode,
  ) {
    final reference = referenceSectors(mode);
    if (sectorIndex >= reference.length) return null;
    final ref = reference[sectorIndex];
    return ref == null ? null : sectorMicros - ref;
  }

  /// Expected lap time if the rest of the lap is driven like the reference:
  /// completed sectors of this lap + reference times of the remaining ones.
  /// In [SectorCompareMode.bestLap] this equals best lap + sum of deltas.
  int? predictedLapMicros(List<int?> completedSectors, SectorCompareMode mode) {
    final reference = referenceSectors(mode);
    if (completedSectors.isEmpty) return null;
    var total = 0;
    for (var i = 0; i < reference.length; i++) {
      final t = i < completedSectors.length
          ? completedSectors[i]
          : reference[i];
      if (t == null) return null;
      total += t;
    }
    return total;
  }

  /// Gap of a complete lap to the best lap *before* it (negative = new
  /// best). Null when there was no earlier lap.
  static int? lapDeltaMicros(Lap lap, List<Lap> earlierLaps) {
    int? best;
    for (final l in earlierLaps) {
      if (best == null || l.timeMicros < best) best = l.timeMicros;
    }
    return best == null ? null : lap.timeMicros - best;
  }
}
