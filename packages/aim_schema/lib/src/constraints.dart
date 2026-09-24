// Constraint checks shared by Validator (reading requests) and Output
// (writing responses).
//
// Each function appends to `errors` rather than returning a verdict, so
// both callers can keep collecting every violation instead of stopping at
// the first one. A response violation is reported with the exact same
// wording a request validation error would use for the same problem, so
// this is the one place that wording is written down.

import 'package:aim_schema/src/errors.dart';

void checkStringConstraints(
  List<ValidationError> errors,
  String path,
  String value,
  int? minLength,
  int? maxLength,
  Pattern? pattern,
) {
  if (minLength != null && value.length < minLength) {
    errors.add(ValidationError(path, 'must be at least $minLength characters'));
  }
  if (maxLength != null && value.length > maxLength) {
    errors.add(ValidationError(path, 'must be at most $maxLength characters'));
  }
  checkPattern(errors, path, value, pattern);
}

void checkPattern(
  List<ValidationError> errors,
  String path,
  String value,
  Pattern? pattern,
) {
  if (pattern != null && pattern.allMatches(value).isEmpty) {
    errors.add(
      ValidationError(
        path,
        'must match the pattern ${describePattern(pattern)}',
      ),
    );
  }
}

void checkNumConstraints(
  List<ValidationError> errors,
  String path,
  num value,
  num? min,
  num? max,
) {
  if (min != null && value < min) {
    errors.add(ValidationError(path, 'must be at least $min'));
  }
  if (max != null && value > max) {
    errors.add(ValidationError(path, 'must be at most $max'));
  }
}

void checkDateTimeBounds(
  List<ValidationError> errors,
  String path,
  DateTime value,
  DateTime? min,
  DateTime? max,
) {
  if (min != null && value.isBefore(min)) {
    errors.add(
      ValidationError(path, 'must be at or after ${min.toIso8601String()}'),
    );
  }
  if (max != null && value.isAfter(max)) {
    errors.add(
      ValidationError(path, 'must be at or before ${max.toIso8601String()}'),
    );
  }
}

void checkListConstraints(
  List<ValidationError> errors,
  String path,
  int length,
  int? minItems,
  int? maxItems,
) {
  if (minItems != null && length < minItems) {
    errors.add(ValidationError(path, 'must have at least $minItems item(s)'));
  }
  if (maxItems != null && length > maxItems) {
    errors.add(ValidationError(path, 'must have at most $maxItems item(s)'));
  }
}

String describePattern(Pattern pattern) =>
    pattern is RegExp ? pattern.pattern : pattern.toString();

/// The message for a value that isn't one of an enum's allowed constants,
/// e.g. `must be one of admin, member`.
String mustBeOneOfMessage(Iterable<Enum> values) =>
    'must be one of ${values.map((v) => v.name).join(', ')}';
