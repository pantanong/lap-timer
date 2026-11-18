import 'dart:io';

import 'package:clock/clock.dart';
import 'package:lap_timer/core/geo/local_point.dart';
import 'package:lap_timer/core/result.dart';
import 'package:lap_timer/features/gps/data/gps_log_repository.dart';
import 'package:lap_timer/features/gps/domain/gps_fix.dart';
import 'package:lap_timer/features/gps/domain/gps_rate_meter.dart';
import 'package:lap_timer/features/gps/domain/simulated_track.dart';
import 'package:test/test.dart';

void main() {
  group('LocalProjection', () {
    test('round-trips latitude/longitude within a millimetre', () {
      final proj = LocalProjection(
        originLatitude: 14.958,
        originLongitude: 103.084,
      );
      const p = LocalPoint(1234.5, -876.25);
      final (lat, lon) = proj.toLatLng(p);
      expect(proj.toLocal(lat, lon).distanceTo(p), lessThan(0.001));
    });
  });

  group('SimulatedTrack', () {
    final track = SimulatedTrack();

    test('racing line is continuous (no jumps between metres)', () {
      for (var d = 0.0; d < track.lapLengthMetres; d += 1) {
        final step = track.pointAt(d).distanceTo(track.pointAt(d + 1));
        expect(step, closeTo(1, 0.01), reason: 'at $d m');
      }
    });

    test('lap closes on itself at the start line', () {
      expect(
        track.pointAt(track.lapLengthMetres).distanceTo(track.pointAt(0)),
        lessThan(1e-6),
      );
    });

    test('has one brake point before each of the two corners', () {
      expect(track.brakePointDistances, hasLength(2));
    });

    test('drive() is deterministic and paced at the requested rate', () {
      final a = track.drive(laps: 1, rateHz: 10).toList();
      final b = track.drive(laps: 1, rateHz: 10).toList();
      expect(a, equals(b));
      expect(a[1].timestampMicros - a[0].timestampMicros, 100000);
    });
  });

  group('GpsFix JSON', () {
    test('round-trips all fields', () {
      const fix = GpsFix(
        timestampMicros: 1700000000123456,
        latitude: 14.95,
        longitude: 103.08,
        speedMetresPerSecond: 41.2,
        headingDegrees: 90,
        horizontalAccuracyMetres: 1.5,
      );
      expect(GpsFix.tryFromJson(fix.toJson()), fix);
    });

    test('returns null instead of throwing on malformed input', () {
      expect(GpsFix.tryFromJson({'t': 'oops'}), isNull);
    });
  });

  test('GpsRateMeter measures 10 Hz from timestamps', () {
    final meter = GpsRateMeter();
    double? rate;
    for (var i = 0; i < 20; i++) {
      rate = meter.add(i * 100000);
    }
    expect(rate, closeTo(10, 1e-9));
  });

  test('GpsLogRepository writes and reads back a log', () async {
    final dir = await Directory.systemTemp.createTemp('gps_logs_test');
    addTearDown(() => dir.delete(recursive: true));
    final repo = GpsLogRepository(
      directory: dir,
      clock: Clock.fixed(DateTime.utc(2026, 11, 18, 9, 30)),
    );
    final fixes = SimulatedTrack().drive(laps: 1).take(30).toList();
    final writer = await repo.startRecording();
    for (final fix in fixes) {
      await writer.add(fix);
    }
    await writer.close();

    final logs = await repo.listLogs();
    expect(logs, hasLength(1));
    final read = await repo.readLog(logs.single);
    expect(read, isA<Ok<List<GpsFix>, Failure>>());
    expect((read as Ok<List<GpsFix>, Failure>).value, fixes);
  });
}
