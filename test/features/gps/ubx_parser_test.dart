import 'package:lap_timer/features/gps/domain/ubx_parser.dart';
import 'package:test/test.dart';

/// NAV-PVT messages captured from a Dragy Pro with nRF Connect (FD02
/// notifications), standing still.
const List<String> _frames = [
  'B5-62-01-07-5C-00-74-CB-8E-13-EA-07-0B-12-13-08-1B-37-16-00-00-00-C3-78-E6-11-03-01-FA-0D-A6-95-F6-3B-F2-14-27-08-10-92-FF-FF-89-FD-FF-FF-0D-02-00-00-8C-02-00-00-09-00-00-00-04-00-00-00-F4-FF-FF-FF-0A-00-00-00-B5-82-4C-00-67-00-00-00-7E-BD-2B-00-DC-00-00-00-5C-40-56-2F-00-00-00-00-00-00-00-00-C9-73',
  'B5-62-01-07-5C-00-EC-E9-8E-13-EA-07-0B-12-13-08-23-37-16-00-00-00-A1-A5-FA-05-03-01-FA-10-AD-95-F6-3B-35-15-27-08-7C-99-FF-FF-F5-04-00-00-C9-01-00-00-4B-02-00-00-0E-00-00-00-F6-FF-FF-FF-0A-00-00-00-12-00-00-00-9A-20-40-00-3E-00-00-00-23-A7-22-00-81-00-00-00-5C-40-56-2F-00-00-00-00-00-00-00-00-B8-7E',
  'B5-62-01-07-5C-00-04-FF-8E-13-EA-07-0B-12-13-08-28-37-16-00-00-00-01-1E-D2-1D-03-01-FA-0F-AE-95-F6-3B-5B-15-27-08-98-9C-FF-FF-11-08-00-00-AC-01-00-00-2A-02-00-00-F9-FF-FF-FF-5B-00-00-00-ED-FF-FF-FF-5B-00-00-00-0C-68-11-02-41-00-00-00-CB-56-3A-00-81-00-00-00-5C-40-56-2F-00-00-00-00-00-00-00-00-53-C4',
];

List<int> _bytes(String hex) => [
  for (final h in hex.split('-')) int.parse(h, radix: 16),
];

void main() {
  test('decodes real Dragy NAV-PVT messages', () {
    final fixes = UbxParser().add(_bytes(_frames.first));
    expect(fixes, hasLength(1));
    final fix = fixes.single;
    final time = DateTime.fromMicrosecondsSinceEpoch(
      fix.timestampMicros,
      isUtc: true,
    );
    expect(time, DateTime.utc(2026, 11, 18, 19, 8, 27, 300, 316));
    expect(fix.latitude, closeTo(13.6778994, 1e-7));
    expect(fix.longitude, closeTo(100.601591, 1e-6));
    expect(fix.speedMetresPerSecond, closeTo(0.010, 1e-9));
    expect(fix.headingDegrees, closeTo(50.14197, 1e-5));
    expect(fix.horizontalAccuracyMetres, closeTo(0.525, 1e-9));
  });

  test('handles messages split across and merged into notifications', () {
    final all = [for (final f in _frames) ..._bytes(f)];
    final parser = UbxParser();
    final fixes = [
      // 20-byte chunks, like BLE notifications with the default MTU.
      for (var i = 0; i < all.length; i += 20)
        ...parser.add(all.sublist(i, (i + 20).clamp(0, all.length))),
    ];
    expect(fixes, hasLength(3));
    expect(fixes.map((f) => f.speedMetresPerSecond), [
      closeTo(0.010, 1e-9),
      closeTo(0.018, 1e-9),
      closeTo(0.091, 1e-9),
    ]);
  });

  test('skips garbage and messages with a bad checksum', () {
    final good = _bytes(_frames.first);
    final bad = List<int>.of(good)..[30] ^= 0xFF;
    final fixes = UbxParser().add([0x00, 0x12, 0xB5, ...bad, 0x55, ...good]);
    expect(fixes, hasLength(1));
  });
}
