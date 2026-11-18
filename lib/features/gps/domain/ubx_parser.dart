import 'dart:typed_data';

import 'package:lap_timer/features/gps/domain/gps_fix.dart';

/// Decoder for u-blox "UBX" binary messages, the protocol many high-rate
/// GNSS receivers (including the Dragy Pro) send over Bluetooth.
///
/// Only NAV-PVT (class 0x01, id 0x07) is used: one message carries the
/// time, position, speed and accuracy of a fix.
///
/// Bluetooth may split or merge messages across notifications, so bytes
/// are buffered, re-synchronised on the `B5 62` header and every message
/// is checked with its Fletcher checksum before use.
class UbxParser {
  static const int _sync1 = 0xB5;
  static const int _sync2 = 0x62;
  static const int _headerLength = 6;
  static const int _maxPayload = 1024;

  final List<int> _buffer = [];

  /// Adds received bytes; returns every complete, valid fix found.
  List<GpsFix> add(List<int> bytes) {
    _buffer.addAll(bytes);
    final fixes = <GpsFix>[];
    while (true) {
      final start = _findSync();
      if (start < 0) {
        // Keep a trailing 0xB5: it may be the start of the next message.
        final keepLast = _buffer.isNotEmpty && _buffer.last == _sync1;
        _buffer.clear();
        if (keepLast) _buffer.add(_sync1);
        break;
      }
      if (start > 0) _buffer.removeRange(0, start);
      if (_buffer.length < _headerLength) break;
      final length = _buffer[4] | (_buffer[5] << 8);
      if (length > _maxPayload) {
        _buffer.removeRange(0, 2); // corrupt header: resync
        continue;
      }
      final total = _headerLength + length + 2;
      if (_buffer.length < total) break;
      final message = Uint8List.fromList(_buffer.sublist(0, total));
      _buffer.removeRange(0, total);
      if (!_checksumOk(message)) continue;
      final fix = _decodeNavPvt(message);
      if (fix != null) fixes.add(fix);
    }
    return fixes;
  }

  int _findSync() {
    for (var i = 0; i + 1 < _buffer.length; i++) {
      if (_buffer[i] == _sync1 && _buffer[i + 1] == _sync2) return i;
    }
    return -1;
  }

  /// 8-bit Fletcher checksum over class, id, length and payload.
  static bool _checksumOk(Uint8List m) {
    var a = 0;
    var b = 0;
    for (var i = 2; i < m.length - 2; i++) {
      a = (a + m[i]) & 0xFF;
      b = (b + a) & 0xFF;
    }
    return a == m[m.length - 2] && b == m[m.length - 1];
  }

  /// NAV-PVT → [GpsFix]; null for other messages or fixes that are not
  /// usable (no 2D/3D fix, or UTC date/time not yet valid).
  static GpsFix? _decodeNavPvt(Uint8List m) {
    if (m[2] != 0x01 || m[3] != 0x07) return null;
    final p = ByteData.sublistView(m, _headerLength, m.length - 2);
    if (p.lengthInBytes < 84) return null;
    final valid = p.getUint8(11);
    final validDate = valid & 0x01 != 0;
    final validTime = valid & 0x02 != 0;
    final fixType = p.getUint8(20);
    final gnssFixOk = p.getUint8(21) & 0x01 != 0;
    if (!validDate || !validTime || !gnssFixOk || fixType < 2) return null;

    final utc = DateTime.utc(
      p.getUint16(4, Endian.little),
      p.getUint8(6),
      p.getUint8(7),
      p.getUint8(8),
      p.getUint8(9),
      p.getUint8(10),
    );
    // `nano` is the signed fraction of the second (may be negative).
    final nano = p.getInt32(16, Endian.little);
    return GpsFix(
      timestampMicros: utc.microsecondsSinceEpoch + nano ~/ 1000,
      longitude: p.getInt32(24, Endian.little) / 1e7,
      latitude: p.getInt32(28, Endian.little) / 1e7,
      speedMetresPerSecond: p.getInt32(60, Endian.little) / 1000,
      headingDegrees: p.getInt32(64, Endian.little) / 1e5,
      horizontalAccuracyMetres: p.getUint32(40, Endian.little) / 1000,
    );
  }
}
