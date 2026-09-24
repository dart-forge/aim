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

/// Thrown by `Output.encode` when a value does not match its declared
/// output.
///
/// Carries every error found, not just the first, the same as
/// [ValidationException] does for requests. Unlike [ValidationException],
/// its [toString] deliberately reports only how many errors there were:
/// aim's default 500 handler puts `$e` straight into the response body, and
/// a response violation is a bug in the server, not something to hand a
/// client the details of.
final class ResponseValidationException implements Exception {
  ResponseValidationException(List<ValidationError> errors)
    : errors = List.unmodifiable(errors),
      assert(errors.isNotEmpty);

  final List<ValidationError> errors;

  @override
  String toString() =>
      'ResponseValidationException: the response did not match its '
      'declared output (${errors.length} error(s))';
}
