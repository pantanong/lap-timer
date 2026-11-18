import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:lap_timer/core/result.dart';
import 'package:lap_timer/features/gps/data/gps_source.dart';
import 'package:lap_timer/features/gps/domain/gps_fix.dart';
import 'package:lap_timer/features/gps/domain/ubx_parser.dart';

/// A Dragy Pro GNSS receiver over Bluetooth Low Energy.
///
/// The Dragy advertises service `0xFD00`; its characteristic `0xFD02`
/// streams u-blox NAV-PVT messages as soon as notifications are enabled
/// (found with nRF Connect). Only notifications are used: this app never
/// writes to the device, so it cannot change its settings or firmware.
///
/// This is the only file that talks to Bluetooth.
class DragyGpsSource implements GpsSource {
  /// Creates the source. The first Dragy found is used.
  DragyGpsSource();

  static final Guid _service = Guid('fd00');
  static final Guid _dataCharacteristic = Guid('fd02');
  static const String _namePrefix = 'DRGPR';
  static const Duration _scanTimeout = Duration(seconds: 12);

  BluetoothDevice? _device;
  BluetoothCharacteristic? _characteristic;

  @override
  String get displayName => 'Dragy Pro';

  @override
  Future<Result<void, GpsFailure>> prepare() async {
    try {
      if (!await FlutterBluePlus.isSupported) {
        return const Err(GpsFailure(GpsFailureKind.bluetoothUnavailable));
      }
      final state = await FlutterBluePlus.adapterState
          .where((s) => s != BluetoothAdapterState.unknown)
          .first
          .timeout(const Duration(seconds: 5));
      if (state != BluetoothAdapterState.on) {
        return const Err(GpsFailure(GpsFailureKind.bluetoothOff));
      }
      final device = await _findDragy();
      if (device == null) {
        return const Err(GpsFailure(GpsFailureKind.deviceNotFound));
      }
      await device.connect(timeout: const Duration(seconds: 15));
      final characteristic = await _findDataCharacteristic(device);
      if (characteristic == null) {
        await device.disconnect();
        return const Err(GpsFailure(GpsFailureKind.deviceNotFound));
      }
      _device = device;
      _characteristic = characteristic;
      return const Ok(null);
    } on FlutterBluePlusException catch (e) {
      return Err(GpsFailure(GpsFailureKind.connectionFailed, cause: e));
    } on TimeoutException catch (e) {
      return Err(GpsFailure(GpsFailureKind.connectionFailed, cause: e));
    }
  }

  @override
  Stream<GpsFix> fixes() {
    final characteristic = _characteristic;
    final device = _device;
    if (characteristic == null || device == null) {
      return const Stream.empty();
    }
    final parser = UbxParser();
    late final StreamController<GpsFix> controller;
    StreamSubscription<List<int>>? data;
    StreamSubscription<BluetoothConnectionState>? connection;
    controller = StreamController<GpsFix>(
      onListen: () async {
        data = characteristic.onValueReceived.listen(
          (bytes) => parser.add(bytes).forEach(controller.add),
        );
        // A lost connection ends the stream (the session then ends too,
        // with everything recorded so far saved).
        connection = device.connectionState.listen((s) {
          if (s == BluetoothConnectionState.disconnected) {
            unawaited(controller.close());
          }
        });
        try {
          await characteristic.setNotifyValue(true);
        } on FlutterBluePlusException catch (e, s) {
          controller.addError(e, s);
          await controller.close();
        }
      },
      onCancel: () async {
        await data?.cancel();
        await connection?.cancel();
        if (device.isConnected) await device.disconnect();
      },
    );
    return controller.stream;
  }

  Future<BluetoothDevice?> _findDragy() async {
    final found = Completer<BluetoothDevice?>();
    final sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final name = r.advertisementData.advName;
        final advertisesService = r.advertisementData.serviceUuids.contains(
          _service,
        );
        if ((name.startsWith(_namePrefix) || advertisesService) &&
            !found.isCompleted) {
          found.complete(r.device);
        }
      }
    });
    try {
      await FlutterBluePlus.startScan(timeout: _scanTimeout);
      return await found.future.timeout(_scanTimeout, onTimeout: () => null);
    } finally {
      await sub.cancel();
      await FlutterBluePlus.stopScan();
    }
  }

  static Future<BluetoothCharacteristic?> _findDataCharacteristic(
    BluetoothDevice device,
  ) async {
    for (final service in await device.discoverServices()) {
      if (service.uuid != _service) continue;
      for (final c in service.characteristics) {
        if (c.uuid == _dataCharacteristic) return c;
      }
    }
    return null;
  }
}
