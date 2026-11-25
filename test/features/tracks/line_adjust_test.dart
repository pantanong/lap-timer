import 'package:lap_timer/core/geo/local_point.dart';
import 'package:lap_timer/features/tracks/domain/gate_line.dart';
import 'package:lap_timer/features/tracks/domain/line_ref.dart';
import 'package:lap_timer/features/tracks/domain/track.dart';
import 'package:test/test.dart';

void main() {
  const drawn = GateLine(
    latitude: 14.96,
    longitude: 103.08,
    axisBearingDegrees: 10,
    widthMetres: 20,
  );

  test('nudge moves the centre by the given metres', () {
    final moved = drawn.movedBy(eastMetres: 5, northMetres: -1);
    final p = LocalProjection(
      originLatitude: 14.96,
      originLongitude: 103.08,
    ).toLocal(moved.latitude, moved.longitude);
    expect(p.x, closeTo(5, 0.01));
    expect(p.y, closeTo(-1, 0.01));
    expect(moved.axisBearingDegrees, 10);
    expect(moved.widthMetres, 20);
  });

  test('rotate wraps a drawn axis within 0–180', () {
    expect(drawn.rotatedBy(-45).axisBearingDegrees, closeTo(145, 1e-9));
    expect(drawn.rotatedBy(175).axisBearingDegrees, closeTo(5, 1e-9));
  });

  test('rotate turns a learned travel direction with the line', () {
    const learned = GateLine(
      latitude: 1,
      longitude: 2,
      travelBearingDegrees: 350,
    );
    final r = learned.rotatedBy(45);
    expect(r.travelBearingDegrees, closeTo(35, 1e-9));
    expect(r.lineAxisDegrees, closeTo(125, 1e-9));
  });

  test('rotate gives a point-only line an orientation', () {
    const point = GateLine(latitude: 1, longitude: 2);
    expect(point.lineAxisDegrees, isNull);
    expect(point.rotatedBy(5).lineAxisDegrees, closeTo(5, 1e-9));
  });

  test('width is clamped', () {
    expect(drawn.withWidth(0).widthMetres, 2);
    expect(drawn.withWidth(30).widthMetres, 30);
  });

  group('LineRef', () {
    const track = Track(
      id: 't',
      name: 'T',
      startFinish: drawn,
      sectorLayouts: [
        SectorLayout(id: 'a:b', name: 'L', splits: [drawn, drawn]),
      ],
    );

    test('encode / decode round trip (layout id with a colon)', () {
      for (final ref in const [
        SingleLineRef(TrackLine.startFinish),
        SingleLineRef(TrackLine.pitEntry),
        SingleLineRef(TrackLine.pitExit),
        SplitLineRef('a:b', 1),
      ]) {
        expect(LineRef.tryDecode(ref.encode()), ref);
      }
      expect(LineRef.tryDecode('split:x'), isNull);
      expect(LineRef.tryDecode(null), isNull);
    });

    test('replace a split keeps the others', () {
      final moved = drawn.movedBy(eastMetres: 3);
      final t = track.withLineAt(const SplitLineRef('a:b', 1), moved);
      expect(t.lineAt(const SplitLineRef('a:b', 1)), moved);
      expect(t.lineAt(const SplitLineRef('a:b', 0)), drawn);
      expect(t.lineAt(const SplitLineRef('a:b', 5)), isNull);
      expect(t.startFinish, drawn);
    });
  });
}
