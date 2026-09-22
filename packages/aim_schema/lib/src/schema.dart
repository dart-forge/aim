import 'package:aim_schema/src/errors.dart';
import 'package:aim_schema/src/field_spec.dart';
import 'package:aim_schema/src/reader.dart';
import 'package:aim_schema/src/recorder.dart';
import 'package:aim_schema/src/validator.dart';

/// The shape of some request data, written as a procedure that reads it.
///
/// ```dart
/// final createUser = Schema((r) => (
///       name: r.string('name', maxLength: 80),
///       age: r.integer('age', min: 0),
///     ));
///
/// final body = createUser.parse(json);
/// body.name; // String
/// ```
///
/// [R] is inferred from what the procedure returns, so a record literal
/// gives the caller named, statically typed fields with no cast. Nothing is
/// generated: the same procedure both validates and describes itself.
final class Schema<R> {
  Schema(this._read);

  final R Function(Reader) _read;

  List<FieldSpec>? _cachedSpec;

  /// What the procedure asks for. Recorded once, on first use.
  ///
  /// Public so that another interpreter of a schema — a nested schema
  /// being recorded, or a writer that turns a declaration into a
  /// specification — can drive it without becoming part of this library.
  List<FieldSpec> get spec {
    final cached = _cachedSpec;
    if (cached != null) return cached;
    final recorder = Recorder();
    _read(recorder);
    return _cachedSpec = recorder.fields;
  }

  /// Validates [input] and returns it with static types.
  ///
  /// Throws [ValidationException] with every error found. Set [coerce]
  /// when the input is text — a query string or headers — so `"34"` reads
  /// as `34`.
  R parse(Map<String, Object?> input, {bool coerce = false}) {
    final validator = Validator(input, spec, coerce: coerce);
    final result = _read(validator);
    validator.finish();
    if (validator.errors.isNotEmpty) {
      throw ValidationException(validator.errors);
    }
    return result;
  }

  /// A JSON Schema description of the same declaration.
  Map<String, Object?> toJsonSchema() {
    final properties = <String, Object?>{};
    final required = <String>[];
    for (final field in spec) {
      properties[field.name] = field.toJsonSchema();
      if (field.required) required.add(field.name);
    }
    return {
      'type': 'object',
      'properties': properties,
      if (required.isNotEmpty) 'required': required,
    };
  }

  /// Runs the declaration against [reader].
  ///
  /// The extension point for anything that interprets a schema rather than
  /// validating it — a nested schema being recorded, or a writer that
  /// turns a declaration into a specification. Application code wants
  /// [parse].
  R readWith(Reader reader) => _read(reader);
}
