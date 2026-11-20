import 'package:lap_timer/features/tracks/domain/gate_line.dart';
import 'package:lap_timer/features/tracks/domain/line_spacing.dart';
import 'package:lap_timer/features/tracks/domain/track.dart';
import 'package:test/test.dart';

void main() {
  const here = GateLine(latitude: 13.6779, longitude: 100.6016);
  // About 110 m north.
  const north = GateLine(latitude: 13.6789, longitude: 100.6016);

  test('all lines set at the same spot are reported', () {
    const track = Track(
      id: 't',
      name: 'S68',
      startFinish: here,
      pitEntry: here,
      pitExit: here,
    );
    final close = findCloseLines(track);
    expect(close, hasLength(3));
    expect(close.first.distanceMetres, lessThan(1));
  });

  test('well separated lines are fine', () {
    const track = Track(
      id: 't',
      name: 'ok',
      startFinish: here,
      pitEntry: north,
    );
    expect(findCloseLines(track), isEmpty);
  });

  test('the same split in two layouts is not a problem', () {
    const track = Track(
      id: 't',
      name: 'layouts',
      startFinish: north,
      sectorLayouts: [
        SectorLayout(id: 'a', name: '3 sectors', splits: [here]),
        SectorLayout(id: 'b', name: '5 sectors', splits: [here]),
      ],
    );
    expect(findCloseLines(track), isEmpty);
  });
}
