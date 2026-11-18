/// Formatting of lap/sector times and deltas for display.
///
/// Times are truncated (not rounded) like official timing, so a display
/// never shows a lap faster than it really was.
library;

/// `1:37.60`, `48.36`, `9.87` or `1:00` — minutes only when needed.
/// [decimals] is 0, 1 or 2 (seconds, tenths or hundredths).
String formatLapTime(int micros, {int decimals = 2}) {
  final negative = micros < 0;
  final abs = micros.abs();
  final perSecond = switch (decimals) {
    0 => 1,
    1 => 10,
    _ => 100,
  };
  final fractionUnits = abs ~/ (1000000 ~/ perSecond);
  final totalSeconds = fractionUnits ~/ perSecond;
  final fraction = fractionUnits % perSecond;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  final fractionText = decimals == 0
      ? ''
      : '.${fraction.toString().padLeft(decimals.clamp(1, 2), '0')}';
  final body = minutes > 0
      ? '$minutes:${seconds.toString().padLeft(2, '0')}$fractionText'
      : '$seconds$fractionText';
  return negative ? '-$body' : body;
}

/// `−0.54` / `+0.49` / `±0.00` with a true minus sign, for deltas.
String formatDelta(int micros) {
  final hundredths = (micros.abs() / 10000).round();
  final text =
      '${hundredths ~/ 100}.${(hundredths % 100).toString().padLeft(2, '0')}';
  if (hundredths == 0) return '±$text';
  return micros < 0 ? '−$text' : '+$text';
}
