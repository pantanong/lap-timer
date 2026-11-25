import 'package:flutter_test/flutter_test.dart';
import 'package:lap_timer/features/tracks/presentation/line_editor_screen.dart';

void main() {
  test('reads coordinates copied from Google Maps', () {
    expect(parseCoordinates('14.958300, 103.084800'), (14.9583, 103.0848));
    expect(parseCoordinates(' 14.9583 103.0848 '), (14.9583, 103.0848));
    expect(parseCoordinates('-33.9,151.2'), (-33.9, 151.2));
  });

  test('rejects text that is not two coordinates', () {
    expect(parseCoordinates('14.95'), isNull);
    expect(parseCoordinates('abc, def'), isNull);
    expect(parseCoordinates('95, 10'), isNull);
  });

  test('formats with 6 decimals', () {
    expect(formatCoordinates(14.9583, 103.0848), '14.958300, 103.084800');
  });
}
