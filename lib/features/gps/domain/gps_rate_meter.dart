/// Measures how many fixes per second a GPS source really delivers, from
/// the fix timestamps (not wall-clock arrival), over a sliding window.
class GpsRateMeter {
  /// Averages over the last [windowSize] fixes.
  GpsRateMeter({this.windowSize = 20});

  /// Number of recent timestamps kept.
  final int windowSize;

  final List<int> _timestamps = [];

  /// Adds a fix time (microseconds) and returns the current rate in Hz, or
  /// null until at least two distinct timestamps are known.
  double? add(int timestampMicros) {
    _timestamps.add(timestampMicros);
    if (_timestamps.length > windowSize) _timestamps.removeAt(0);
    if (_timestamps.length < 2) return null;
    final spanMicros = _timestamps.last - _timestamps.first;
    if (spanMicros <= 0) return null;
    return (_timestamps.length - 1) * 1e6 / spanMicros;
  }

  /// Forgets all timestamps.
  void reset() => _timestamps.clear();
}
