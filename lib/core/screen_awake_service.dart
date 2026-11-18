import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen on while timing. Behind an interface so tests (and
/// future platforms) can swap the implementation.
abstract interface class ScreenAwakeService {
  /// Prevents the screen from turning off.
  Future<void> keepOn();

  /// Lets the screen turn off normally again.
  Future<void> release();
}

/// Real implementation using `wakelock_plus`.
class WakelockScreenAwakeService implements ScreenAwakeService {
  /// Creates the service.
  const WakelockScreenAwakeService();

  @override
  Future<void> keepOn() => WakelockPlus.enable();

  @override
  Future<void> release() => WakelockPlus.disable();
}

/// The screen-awake service in use.
final Provider<ScreenAwakeService> screenAwakeServiceProvider =
    Provider<ScreenAwakeService>((ref) => const WakelockScreenAwakeService());
