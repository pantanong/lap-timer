/// A typed outcome for operations that can fail in an expected way
/// (file I/O, permissions, hardware), so callers must handle both cases.
///
/// Use an exhaustive `switch` on [Ok] / [Err] instead of try/catch.
library;

/// Base type for every expected failure. [code] is stable and
/// language-independent so the UI can map it to a localized message.
abstract class Failure {
  /// Creates a failure with an optional underlying [cause].
  const Failure({this.cause});

  /// Stable machine-readable identifier, e.g. `gps.permission_denied`.
  String get code;

  /// The original error, kept for logging only.
  final Object? cause;

  @override
  String toString() => '$runtimeType($code, cause: $cause)';
}

/// Either a success value of type [T] or a failure of type [F].
sealed class Result<T, F extends Failure> {
  const Result();
}

/// The success case, carrying [value].
final class Ok<T, F extends Failure> extends Result<T, F> {
  /// Wraps a successful [value].
  const Ok(this.value);

  /// The produced value.
  final T value;
}

/// The failure case, carrying [failure].
final class Err<T, F extends Failure> extends Result<T, F> {
  /// Wraps an expected [failure].
  const Err(this.failure);

  /// What went wrong.
  final F failure;
}
