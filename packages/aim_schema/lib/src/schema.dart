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

  /// Whether the recording pass for this [Schema] is currently running.
  ///
  /// Set for the duration of the one-time [spec] build and cleared again
  /// before it returns — it is not state that survives a [parse] call, only
  /// a guard against a schema recursing into its own recording. See [spec].
  bool _recording = false;

  /// What the procedure asks for. Recorded once, on first use.
  ///
  /// Returns an unmodifiable list: this is handed to other interpreters of
  /// the schema (see below) and to [Validator], which trusts it to stay
  /// exactly what it recorded for the lifetime of the process — a `Schema`
  /// is normally a top-level `final` shared by every request, so a caller
  /// mutating this list (say, sorting it for a stable OpenAPI export) would
  /// corrupt every future [parse] call, not just its own copy.
  ///
  /// Public so that another interpreter of a schema — a nested schema
  /// being recorded, or a writer that turns a declaration into a
  /// specification — can drive it without becoming part of this library.
  List<FieldSpec> get spec {
    final cached = _cachedSpec;
    if (cached != null) return cached;
    if (_recording) {
      throw StateError(
        'This schema references itself: recording its fields asks, '
        'directly or through a nested field, for the spec of this very '
        'Schema instance while that spec is still being built. A '
        'tree-shaped payload cannot be declared this way — read the '
        'recursive part as a plain, unvalidated value (or a bounded number '
        'of levels) and check it in your own code instead.',
      );
    }
    _recording = true;
    final recorder = Recorder();
    try {
      _read(recorder);
    } catch (error) {
      // Two kinds of error are already self-explanatory and must not be
      // re-wrapped:
      //
      // - A StateError from this very getter — the recursion guard above,
      //   or another schema's own "computes on a value" error surfacing
      //   through a nested object/objectList read during this recording
      //   pass. Re-wrapping it here would prepend another copy of this
      //   catch clause's own message every level of nesting, and for a
      //   self-referential schema that repeats once per recursion —
      //   hundreds of times for a modest tree — before finally failing
      //   with a StackOverflowError once the message itself is enormous.
      // - A ReaderArgumentError a Reader method raised about its own
      //   arguments (e.g. enumValue's `values` being empty) — a problem
      //   with the schema's declaration, not with computing on a value it
      //   read. Deliberately narrower than "any ArgumentError": RangeError
      //   is itself an ArgumentError, and ''.substring(0, 3) — the
      //   ordinary "computes on a value" case just below — throws exactly
      //   that.
      //
      // Passing either through unchanged keeps the error to the one
      // message that actually names the rule that was broken.
      if (error is StateError || error is ReaderArgumentError) rethrow;
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
    } finally {
      _recording = false;
    }
    return _cachedSpec = List.unmodifiable(recorder.fields);
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
  ///
  /// A field the procedure reads more than once — legitimate, when one
  /// input field feeds two record fields — is described here by whichever
  /// read happened last, since `properties` is a map keyed by the field's
  /// name. `required` is deduplicated instead of following that same
  /// last-wins rule, because JSON Schema requires its entries to be unique.
  /// If the two reads disagree on a constraint (one caps `maxLength` at 80,
  /// the other doesn't), the description reflects only the one that's kept
  /// here — but [parse] still enforces both, since it runs every read
  /// against the real input regardless of what this method reports.
  Map<String, Object?> toJsonSchema() {
    final properties = <String, Object?>{};
    final required = <String>[];
    for (final field in spec) {
      properties[field.name] = field.toJsonSchema();
      if (field.required && !required.contains(field.name)) {
        required.add(field.name);
      }
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
  ///
  /// This is also how a third-party [Reader] implementation gets a nested
  /// value: [Recorder] is not exported, so it has no way to manufacture a
  /// placeholder of an arbitrary record type on its own. Call
  /// `schema.readWith(this)` recursively instead — running the nested
  /// schema's procedure against the same reader is the intended way to
  /// implement `object`, `objectOrNull`, and `objectList`.
  R readWith(Reader reader) => _read(reader);
}
