import 'package:aim_core/aim_core.dart';
import 'package:aim_schema/src/schema.dart';

/// Adds schema-validated reading to [Context].
///
/// This is one of only two files in this package that import `aim_core`:
/// the rest is pure Dart so it can be interpreted the same way regardless
/// of which of aim's runtimes it runs on.
extension SchemaContext<E extends Variables> on Context<E> {
  /// Reads the JSON body and validates it against [schema].
  ///
  /// Throws [ValidationException]. Add [validationErrorsAsBadRequest] to
  /// turn that into a 400 response instead of reaching the error handler.
  Future<R> parse<R>(Schema<R> schema) async => schema.parse(await req.json());

  /// Validates the query string against [schema].
  ///
  /// A query string is text, so this coerces: `?age=34` reads as `34`.
  R parseQuery<R>(Schema<R> schema) => schema.parse(query, coerce: true);
}
