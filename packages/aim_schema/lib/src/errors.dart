/// One thing that was wrong with the input.
final class ValidationError {
  const ValidationError(this.path, this.message);

  /// Where it was wrong: `name`, `address.city`, `tags[2]`.
  final String path;

  final String message;

  @override
  String toString() => '$path: $message';
}

/// Thrown by a [Reader] method when its own arguments make a schema
/// unsatisfiable no matter what a request supplies — e.g. `enumValue` given
/// no values to accept.
///
/// Not exported. This exists only so [Schema.spec]'s catch-all can tell such
/// an error apart from an ordinary [ArgumentError] — [RangeError] is one —
/// that comes from a schema computing on the placeholder value the
/// recording pass hands back; that case gets rewritten to name the rule
/// that was actually broken. A [ReaderArgumentError] is already
/// self-explanatory, so it passes through unchanged instead.
final class ReaderArgumentError extends ArgumentError {
  ReaderArgumentError.value(super.value, super.name, super.message)
    : super.value();
}

/// Thrown by [Schema.parse] when the input does not match.
///
/// Carries every error found, not just the first, so a caller can fix them
/// in one round trip.
final class ValidationException implements Exception {
  ValidationException(List<ValidationError> errors)
    : errors = List.unmodifiable(errors),
      assert(errors.isNotEmpty);

  final List<ValidationError> errors;

  @override
  String toString() => 'ValidationException(${errors.join('; ')})';
}
