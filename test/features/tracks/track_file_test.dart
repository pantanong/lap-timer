import 'package:lap_timer/features/tracks/domain/gate_line.dart';
import 'package:lap_timer/features/tracks/domain/track.dart';
import 'package:lap_timer/features/tracks/domain/track_file.dart';
import 'package:test/test.dart';

void main() {
  const track = Track(
    id: 'a',
    name: 'Buriram',
    startFinish: GateLine(
      latitude: 14.9583,
      longitude: 103.0848,
      travelBearingDegrees: 92,
    ),
    sectorLayouts: [
      SectorLayout(
        id: 'l',
        name: 'Buriram (3 Sectors)',
        splits: [
          GateLine(latitude: 14.96, longitude: 103.09, axisBearingDegrees: 10),
          GateLine(latitude: 14.961, longitude: 103.091),
        ],
      ),
    ],
    pitEntry: GateLine(latitude: 14.9581, longitude: 103.0846),
  );

  test('export → import keeps every line exactly', () {
    final back = TrackFile.tryDecode(TrackFile.encode(track));
    expect(back, isNotNull);
    expect(back?.name, 'Buriram');
    expect(back?.startFinish, track.startFinish);
    expect(back?.pitEntry, track.pitEntry);
    expect(
      back?.sectorLayouts.single.splits,
      track.sectorLayouts.single.splits,
    );
  });

  test('the file is readable text with the coordinates in it', () {
    final text = TrackFile.encode(track);
    expect(text, contains('"format": "lap-timer-track"'));
    expect(text, contains('14.9583'));
    expect(text, contains('103.0848'));
  });

  test('rejects other files and newer versions', () {
    expect(TrackFile.tryDecode('hello'), isNull);
    expect(TrackFile.tryDecode('{"format":"other","version":1}'), isNull);
    expect(
      TrackFile.tryDecode(
        '{"format":"lap-timer-track","version":99,"track":{}}',
      ),
      isNull,
    );
  });

  test('import gets a new id and never overwrites a same-name track', () {
    final imported = TrackFile.asNewTrack(track, [track], newId: 'b');
    expect(imported.id, 'b');
    expect(imported.name, 'Buriram (imported)');
    expect(imported.startFinish, track.startFinish);
  });

  test('safe file name', () {
    expect(
      TrackFile.fileNameFor(track.copyWith(name: 'Bira / Pattaya #1')),
      'Bira_Pattaya_1.laptrack.json',
    );
  });
}
