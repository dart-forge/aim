import 'dart:convert';

import 'package:aim_core/aim_core.dart';
import 'package:aim_schema/src/errors.dart';
import 'package:aim_schema/src/schema.dart';

/// Adds schema-validated reading to [Context].
///
/// This is one of only two files in this package that import `aim_core`:
/// the rest is pure Dart so it can be interpreted the same way regardless
/// of which of aim's runtimes it runs on.
extension SchemaContext<E extends Variables> on Context<E> {
  /// Reads the JSON body and validates it against [schema].
  ///
  /// Throws [ValidationException] — including when the body is not valid
  /// JSON, or is valid JSON that is not an object (an array, a string,
  /// `null`). Those are the client's mistake like any failed field, so they
  /// get the same 400 from [validationErrorsAsBadRequest], with an empty
  /// path because no single field is at fault.
  Future<R> parse<R>(Schema<R> schema) async {
    // Decoded here rather than through req.json(), which casts to a map and
    // so throws a TypeError or FormatException that no validation handler
    // recognises: a malformed body became a 500.
    final Object? decoded;
    try {
      decoded = jsonDecode(await req.text());
    } on FormatException {
      throw ValidationException([
        const ValidationError('', 'the request body is not valid JSON'),
      ]);
    }
    if (decoded is! Map<String, Object?>) {
      throw ValidationException([
        const ValidationError('', 'the request body must be a JSON object'),
      ]);
    }
    return schema.parse(decoded);
  }

  /// Validates the query string against [schema].
  ///
  /// A query string is text, so this coerces: `?age=34` reads as `34`.
  R parseQuery<R>(Schema<R> schema) => schema.parse(query, coerce: true);
}
