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
    try {
      _read(recorder);
    } catch (error) {
      // The recording pass has no real input, so every read returns a
      // placeholder ('' or 0) instead of a value from a request. A
      // procedure that computes on what it reads — DateTime.parse(r.string(
      // 'date')), r.string('name').substring(0, 3) — runs that computation
      // against the placeholder here and typically throws (a RangeError, a
      // FormatException, ...). It already fails safely: nothing gets
      // cached and the exception propagates. But the raw error names a
      // symptom, not the rule, so it is wrapped here to say what a schema
      // may not do. This is not the determinism check in Validator: that
      // one is about asking for the same fields every time; this one is
      // about not doing arithmetic or parsing on a value right after
      // reading it.
      throw StateError(
        'This schema computes on a value it just read, which fails during '
        'the recording pass because every read there returns a placeholder '
        "('' or 0) rather than real input: $error\n"
        'A schema must not do arithmetic, parsing, or substring work on a '
        'value it reads — e.g. DateTime.parse(r.string(\'date\')) or '
        "r.string('name').substring(0, 3) — it may only read fields and "
        'hand the raw values back.',
      );
    }
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
