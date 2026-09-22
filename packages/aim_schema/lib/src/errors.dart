/// One thing that was wrong with the input.
final class ValidationError {
  const ValidationError(this.path, this.message);

  /// Where it was wrong: `name`, `address.city`, `tags[2]`.
  final String path;

  final String message;

  @override
  String toString() => '$path: $message';
}

/// Thrown by [Schema.parse] when the input does not match.
///
/// Carries every error found, not just the first, so a caller can fix them
/// in one round trip.
final class ValidationException implements Exception {
  ValidationException(this.errors) : assert(errors.isNotEmpty);

  final List<ValidationError> errors;

  @override
  String toString() => 'ValidationException(${errors.join('; ')})';
}
