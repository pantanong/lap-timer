import 'package:lap_timer/features/gps/data/gps_source.dart';
import 'package:lap_timer/l10n/generated/app_localizations.dart';

/// Maps a [GpsFailure] to a user-facing, localized sentence.
String gpsFailureMessage(AppLocalizations l10n, GpsFailure failure) =>
    switch (failure.kind) {
      GpsFailureKind.serviceDisabled => l10n.errorGpsServiceDisabled,
      GpsFailureKind.permissionDenied => l10n.errorGpsPermissionDenied,
      GpsFailureKind.permissionDeniedForever =>
        l10n.errorGpsPermissionDeniedForever,
      GpsFailureKind.logUnavailable => l10n.errorGpsLogUnavailable,
      GpsFailureKind.bluetoothUnavailable => l10n.errorBluetoothUnavailable,
      GpsFailureKind.bluetoothOff => l10n.errorBluetoothOff,
      GpsFailureKind.deviceNotFound => l10n.errorDragyNotFound,
      GpsFailureKind.connectionFailed => l10n.errorDragyConnection,
    };
