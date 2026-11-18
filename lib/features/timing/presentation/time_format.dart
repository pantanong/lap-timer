/// Formatting of lap/sector times and deltas for display.
///
/// Times are truncated (not rounded) like official timing, so a display
/// never shows a lap faster than it really was.
library;

/// `1:37.60`, `48.36`, or `9.87` — minutes only when needed.
/// [decimals] is 1 or 2 (tenths or hundredths).
String formatLapTime(int micros, {int decimals = 2}) {
  final negative = micros < 0;
  final abs = micros.abs();
  final unit = decimals == 1 ? 100000 : 10000;
  final fractionUnits = abs ~/ unit;
  final totalSeconds = fractionUnits ~/ (decimals == 1 ? 10 : 100);
  final fraction = fractionUnits % (decimals == 1 ? 10 : 100);
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  final fractionText = fraction.toString().padLeft(decimals, '0');
  final body = minutes > 0
      ? '$minutes:${seconds.toString().padLeft(2, '0')}.$fractionText'
      : '$seconds.$fractionText';
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
