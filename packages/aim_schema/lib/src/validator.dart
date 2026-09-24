import 'package:aim_schema/src/constraints.dart' as constraints;
import 'package:aim_schema/src/errors.dart';
import 'package:aim_schema/src/field_spec.dart';
import 'package:aim_schema/src/reader.dart';
import 'package:aim_schema/src/recorder.dart';
import 'package:aim_schema/src/schema.dart';

/// Validates real input against what the recording pass saw, and returns
/// the values with static types.
///
/// Every method starts by checking the procedure is asking for what it
/// asked for while recording — see [_expect]. That check is what makes it
/// safe for a schema's procedure to run twice with two different meanings.
final class Validator implements Reader {
  Validator(
    this._input,
    this._spec, {
    required this.coerce,
    this._path = '',
    List<ValidationError>? errors,
  }) : errors = errors ?? <ValidationError>[];

  final Map<String, Object?> _input;
  final List<FieldSpec> _spec;

  /// Whether to accept a string standing in for a scalar, such as `'34'`
  /// for an [integer] field. Set this when the input is text throughout —
  /// a query string or headers — rather than JSON, where types already
  /// distinguish `34` from `'34'`.
  final bool coerce;
  final String _path;

  /// Every problem found so far. [Schema.parse] throws a
  /// [ValidationException] carrying these once the procedure has run.
  ///
  /// A nested [object] or [objectList] call shares this same list with the
  /// child [Validator] it creates, rather than merging a separate one in
  /// afterwards, so every error — at any depth — ends up in one flat list
  /// in the order it was found.
  final List<ValidationError> errors;

  int _index = 0;

  /// The name of the last field this reader was asked for and matched
  /// against the recording. Reported in the determinism error so it points
  /// at the value the procedure branched on, not just where it diverged.
  String? _lastFieldRead;

  /// Checks the procedure is asking for what it asked for while recording.
  ///
  /// Name, type, and [format] are compared — [format] because [type] alone
  /// can't tell a plain string apart from a `dateTime` or an `enumValue`
  /// (see [FieldSpec.format]). The constraint *values* (`minLength`,
  /// `pattern`, and the like) come from the recording pass regardless, so a
  /// constraint computed from a value would describe one bound and enforce
  /// another — documented, not guarded.
  void _expect(String name, String type, {String? format}) {
    final mismatched =
        _index >= _spec.length ||
        _spec[_index].name != name ||
        _spec[_index].type != type ||
        _spec[_index].format != format;
    if (mismatched) {
      final expected = _index < _spec.length
          ? '"${_spec[_index].name}" (${_spec[_index].type})'
          : 'nothing more';
      final lastRead = _lastFieldRead;
      final afterClause = lastRead == null
          ? ''
          : ' right after reading "$lastRead",';
      throw StateError(
        'This schema depends on the data it reads:$afterClause it asked '
        'for $expected while recording, and now it asks for "$name" '
        '($type). A schema must read the same fields every time.',
      );
    }
    _lastFieldRead = name;
    _index++;
  }

  /// Called after the procedure returns, to catch one that stopped early —
  /// asked for fewer fields than it did while recording, without ever
  /// disagreeing on a name or type.
  void finish() {
    if (_index != _spec.length) {
      throw StateError(
        'This schema depends on the data it reads: it asked for $_index '
        'field(s) this time, but ${_spec.length} while recording. A '
        'schema must read the same fields every time.',
      );
    }
  }

  String _pathOf(String name) => _path.isEmpty ? name : '$_path.$name';

  @override
  String string(
    String name, {
    int? minLength,
    int? maxLength,
    Pattern? pattern,
  }) {
    _expect(name, 'string');
    final path = _pathOf(name);
    final value = _input[name];
    if (value == null) {
      errors.add(ValidationError(path, 'is required'));
      return '';
    }
    final resolved = _asString(value);
    if (resolved == null) {
      errors.add(ValidationError(path, 'must be a string'));
      return '';
    }
    _checkStringConstraints(path, resolved, minLength, maxLength, pattern);
    return resolved;
  }

  @override
  int integer(String name, {int? min, int? max}) {
    _expect(name, 'integer');
    final path = _pathOf(name);
    final value = _input[name];
    if (value == null) {
      errors.add(ValidationError(path, 'is required'));
      return 0;
    }
    final resolved = _asInteger(value);
    if (resolved == null) {
      errors.add(ValidationError(path, 'must be an integer'));
      return 0;
    }
    _checkNumConstraints(path, resolved, min, max);
    return resolved;
  }

  @override
  double number(String name, {double? min, double? max}) {
    _expect(name, 'number');
    final path = _pathOf(name);
    final value = _input[name];
    if (value == null) {
      errors.add(ValidationError(path, 'is required'));
      return 0;
    }
    final resolved = _asNumber(value);
    if (resolved == null) {
      errors.add(ValidationError(path, 'must be a number'));
      return 0;
    }
    _checkNumConstraints(path, resolved, min, max);
    return resolved;
  }

  @override
  bool boolean(String name) {
    _expect(name, 'boolean');
    final path = _pathOf(name);
    final value = _input[name];
    if (value == null) {
      errors.add(ValidationError(path, 'is required'));
      return false;
    }
    final resolved = _asBoolean(value);
    if (resolved == null) {
      errors.add(ValidationError(path, 'must be a boolean'));
      return false;
    }
    return resolved;
  }

  @override
  DateTime dateTime(String name, {DateTime? min, DateTime? max}) {
    _expect(name, 'string', format: 'date-time');
    final path = _pathOf(name);
    final value = _input[name];
    if (value == null) {
      errors.add(ValidationError(path, 'is required'));
      return _epoch;
    }
    final resolved = _asDateTime(value);
    if (resolved == null) {
      errors.add(ValidationError(path, 'must be an ISO 8601 date-time'));
      return _epoch;
    }
    _checkDateTimeBounds(path, resolved, min, max);
    return resolved;
  }

  @override
  String? stringOrNull(
    String name, {
    int? minLength,
    int? maxLength,
    Pattern? pattern,
  }) {
    // Recorded with type 'string', same as [string] — required is a
    // property of the field, not something [_expect] checks.
    _expect(name, 'string');
    final path = _pathOf(name);
    final value = _input[name];
    if (value == null) return null;
    final resolved = _asString(value);
    if (resolved == null) {
      errors.add(ValidationError(path, 'must be a string'));
      return null;
    }
    _checkStringConstraints(path, resolved, minLength, maxLength, pattern);
    return resolved;
  }

  @override
  int? integerOrNull(String name, {int? min, int? max}) {
    _expect(name, 'integer');
    final path = _pathOf(name);
    final value = _input[name];
    if (value == null) return null;
    final resolved = _asInteger(value);
    if (resolved == null) {
      errors.add(ValidationError(path, 'must be an integer'));
      return null;
    }
    _checkNumConstraints(path, resolved, min, max);
    return resolved;
  }

  @override
  double? numberOrNull(String name, {double? min, double? max}) {
    _expect(name, 'number');
    final path = _pathOf(name);
    final value = _input[name];
    if (value == null) return null;
    final resolved = _asNumber(value);
    if (resolved == null) {
      errors.add(ValidationError(path, 'must be a number'));
      return null;
    }
    _checkNumConstraints(path, resolved, min, max);
    return resolved;
  }

  @override
  bool? booleanOrNull(String name) {
    _expect(name, 'boolean');
    final path = _pathOf(name);
    final value = _input[name];
    if (value == null) return null;
    final resolved = _asBoolean(value);
    if (resolved == null) {
      errors.add(ValidationError(path, 'must be a boolean'));
      return null;
    }
    return resolved;
  }

  @override
  DateTime? dateTimeOrNull(String name, {DateTime? min, DateTime? max}) {
    _expect(name, 'string', format: 'date-time');
    final path = _pathOf(name);
    final value = _input[name];
    if (value == null) return null;
    final resolved = _asDateTime(value);
    if (resolved == null) {
      errors.add(ValidationError(path, 'must be an ISO 8601 date-time'));
      return null;
    }
    _checkDateTimeBounds(path, resolved, min, max);
    return resolved;
  }

  @override
  T enumValue<T extends Enum>(String name, List<T> values) {
    if (values.isEmpty) {
      throw ReaderArgumentError.value(
        values,
        'values',
        'enumValue needs at least one value to accept; an enum with no '
            'constants can never be satisfied',
      );
    }
    _expect(name, 'string', format: 'enum');
    final path = _pathOf(name);
    final value = _input[name];
    if (value == null) {
      errors.add(ValidationError(path, 'is required'));
      return values.first;
    }
    final resolved = _asEnumValue(value, values);
    if (resolved == null) {
      errors.add(
        ValidationError(
          path,
          'must be one of ${values.map((v) => v.name).join(', ')}',
        ),
      );
      return values.first;
    }
    return resolved;
  }

  @override
  T? enumValueOrNull<T extends Enum>(String name, List<T> values) {
    _expect(name, 'string', format: 'enum');
    final path = _pathOf(name);
    final value = _input[name];
    if (value == null) return null;
    final resolved = _asEnumValue(value, values);
    if (resolved == null) {
      errors.add(
        ValidationError(
          path,
          'must be one of ${values.map((v) => v.name).join(', ')}',
        ),
      );
      return null;
    }
    return resolved;
  }

  @override
  List<String> stringList(
    String name, {
    int? minItems,
    int? maxItems,
    Pattern? pattern,
  }) {
    _expect(name, 'array');
    final path = _pathOf(name);
    final value = _input[name];
    if (value == null) {
      errors.add(ValidationError(path, 'is required'));
      return const [];
    }
    if (value is! List) {
      errors.add(ValidationError(path, 'must be an array'));
      return const [];
    }
    final result = <String>[];
    for (var i = 0; i < value.length; i++) {
      final elementPath = '$path[$i]';
      final resolved = _asString(value[i]);
      if (resolved == null) {
        errors.add(ValidationError(elementPath, 'must be a string'));
      } else {
        _checkPattern(elementPath, resolved, pattern);
        result.add(resolved);
      }
    }
    _checkListConstraints(path, value.length, minItems, maxItems);
    return result;
  }

  @override
  List<String>? stringListOrNull(
    String name, {
    int? minItems,
    int? maxItems,
    Pattern? pattern,
  }) {
    _expect(name, 'array');
    final path = _pathOf(name);
    final value = _input[name];
    if (value == null) return null;
    if (value is! List) {
      errors.add(ValidationError(path, 'must be an array'));
      return null;
    }
    final result = <String>[];
    for (var i = 0; i < value.length; i++) {
      final elementPath = '$path[$i]';
      final resolved = _asString(value[i]);
      if (resolved == null) {
        errors.add(ValidationError(elementPath, 'must be a string'));
      } else {
        _checkPattern(elementPath, resolved, pattern);
        result.add(resolved);
      }
    }
    _checkListConstraints(path, value.length, minItems, maxItems);
    return result;
  }

  @override
  List<int> integerList(String name, {int? minItems, int? maxItems}) {
    _expect(name, 'array');
    final path = _pathOf(name);
    final value = _input[name];
    if (value == null) {
      errors.add(ValidationError(path, 'is required'));
      return const [];
    }
    if (value is! List) {
      errors.add(ValidationError(path, 'must be an array'));
      return const [];
    }
    final result = <int>[];
    for (var i = 0; i < value.length; i++) {
      final resolved = _asInteger(value[i]);
      if (resolved == null) {
        errors.add(ValidationError('$path[$i]', 'must be an integer'));
      } else {
        result.add(resolved);
      }
    }
    _checkListConstraints(path, value.length, minItems, maxItems);
    return result;
  }

  @override
  List<int>? integerListOrNull(String name, {int? minItems, int? maxItems}) {
    _expect(name, 'array');
    final path = _pathOf(name);
    final value = _input[name];
    if (value == null) return null;
    if (value is! List) {
      errors.add(ValidationError(path, 'must be an array'));
      return null;
    }
    final result = <int>[];
    for (var i = 0; i < value.length; i++) {
      final resolved = _asInteger(value[i]);
      if (resolved == null) {
        errors.add(ValidationError('$path[$i]', 'must be an integer'));
      } else {
        result.add(resolved);
      }
    }
    _checkListConstraints(path, value.length, minItems, maxItems);
    return result;
  }

  @override
  List<double> numberList(String name, {int? minItems, int? maxItems}) {
    _expect(name, 'array');
    final path = _pathOf(name);
    final value = _input[name];
    if (value == null) {
      errors.add(ValidationError(path, 'is required'));
      return const [];
    }
    if (value is! List) {
      errors.add(ValidationError(path, 'must be an array'));
      return const [];
    }
    final result = <double>[];
    for (var i = 0; i < value.length; i++) {
      final resolved = _asNumber(value[i]);
      if (resolved == null) {
        errors.add(ValidationError('$path[$i]', 'must be a number'));
      } else {
        result.add(resolved);
      }
    }
    _checkListConstraints(path, value.length, minItems, maxItems);
    return result;
  }

  @override
  List<double>? numberListOrNull(String name, {int? minItems, int? maxItems}) {
    _expect(name, 'array');
    final path = _pathOf(name);
    final value = _input[name];
    if (value == null) return null;
    if (value is! List) {
      errors.add(ValidationError(path, 'must be an array'));
      return null;
    }
    final result = <double>[];
    for (var i = 0; i < value.length; i++) {
      final resolved = _asNumber(value[i]);
      if (resolved == null) {
        errors.add(ValidationError('$path[$i]', 'must be a number'));
      } else {
        result.add(resolved);
      }
    }
    _checkListConstraints(path, value.length, minItems, maxItems);
    return result;
  }

  @override
  List<bool> booleanList(String name, {int? minItems, int? maxItems}) {
    _expect(name, 'array');
    final path = _pathOf(name);
    final value = _input[name];
    if (value == null) {
      errors.add(ValidationError(path, 'is required'));
      return const [];
    }
    if (value is! List) {
      errors.add(ValidationError(path, 'must be an array'));
      return const [];
    }
    final result = <bool>[];
    for (var i = 0; i < value.length; i++) {
      final resolved = _asBoolean(value[i]);
      if (resolved == null) {
        errors.add(ValidationError('$path[$i]', 'must be a boolean'));
      } else {
        result.add(resolved);
      }
    }
    _checkListConstraints(path, value.length, minItems, maxItems);
    return result;
  }

  @override
  List<bool>? booleanListOrNull(String name, {int? minItems, int? maxItems}) {
    _expect(name, 'array');
    final path = _pathOf(name);
    final value = _input[name];
    if (value == null) return null;
    if (value is! List) {
      errors.add(ValidationError(path, 'must be an array'));
      return null;
    }
    final result = <bool>[];
    for (var i = 0; i < value.length; i++) {
      final resolved = _asBoolean(value[i]);
      if (resolved == null) {
        errors.add(ValidationError('$path[$i]', 'must be a boolean'));
      } else {
        result.add(resolved);
      }
    }
    _checkListConstraints(path, value.length, minItems, maxItems);
    return result;
  }

  @override
  List<DateTime> dateTimeList(
    String name, {
    int? minItems,
    int? maxItems,
    DateTime? min,
    DateTime? max,
  }) {
    _expect(name, 'array', format: 'date-time');
    final path = _pathOf(name);
    final value = _input[name];
    if (value == null) {
      errors.add(ValidationError(path, 'is required'));
      return const [];
    }
    if (value is! List) {
      errors.add(ValidationError(path, 'must be an array'));
      return const [];
    }
    final result = <DateTime>[];
    for (var i = 0; i < value.length; i++) {
      final elementPath = '$path[$i]';
      final resolved = _asDateTime(value[i]);
      if (resolved == null) {
        errors.add(
          ValidationError(elementPath, 'must be an ISO 8601 date-time'),
        );
      } else {
        _checkDateTimeBounds(elementPath, resolved, min, max);
        result.add(resolved);
      }
    }
    _checkListConstraints(path, value.length, minItems, maxItems);
    return result;
  }

  @override
  List<DateTime>? dateTimeListOrNull(
    String name, {
    int? minItems,
    int? maxItems,
    DateTime? min,
    DateTime? max,
  }) {
    _expect(name, 'array', format: 'date-time');
    final path = _pathOf(name);
    final value = _input[name];
    if (value == null) return null;
    if (value is! List) {
      errors.add(ValidationError(path, 'must be an array'));
      return null;
    }
    final result = <DateTime>[];
    for (var i = 0; i < value.length; i++) {
      final elementPath = '$path[$i]';
      final resolved = _asDateTime(value[i]);
      if (resolved == null) {
        errors.add(
          ValidationError(elementPath, 'must be an ISO 8601 date-time'),
        );
      } else {
        _checkDateTimeBounds(elementPath, resolved, min, max);
        result.add(resolved);
      }
    }
    _checkListConstraints(path, value.length, minItems, maxItems);
    return result;
  }

  @override
  List<T> enumList<T extends Enum>(
    String name,
    List<T> values, {
    int? minItems,
    int? maxItems,
  }) {
    _expect(name, 'array', format: 'enum');
    final path = _pathOf(name);
    final value = _input[name];
    if (value == null) {
      errors.add(ValidationError(path, 'is required'));
      return const [];
    }
    if (value is! List) {
      errors.add(ValidationError(path, 'must be an array'));
      return const [];
    }
    final result = <T>[];
    for (var i = 0; i < value.length; i++) {
      final elementPath = '$path[$i]';
      final resolved = _asEnumValue(value[i], values);
      if (resolved == null) {
        errors.add(
          ValidationError(
            elementPath,
            'must be one of ${values.map((v) => v.name).join(', ')}',
          ),
        );
      } else {
        result.add(resolved);
      }
    }
    _checkListConstraints(path, value.length, minItems, maxItems);
    return result;
  }

  @override
  List<T>? enumListOrNull<T extends Enum>(
    String name,
    List<T> values, {
    int? minItems,
    int? maxItems,
  }) {
    _expect(name, 'array', format: 'enum');
    final path = _pathOf(name);
    final value = _input[name];
    if (value == null) return null;
    if (value is! List) {
      errors.add(ValidationError(path, 'must be an array'));
      return null;
    }
    final result = <T>[];
    for (var i = 0; i < value.length; i++) {
      final elementPath = '$path[$i]';
      final resolved = _asEnumValue(value[i], values);
      if (resolved == null) {
        errors.add(
          ValidationError(
            elementPath,
            'must be one of ${values.map((v) => v.name).join(', ')}',
          ),
        );
      } else {
        result.add(resolved);
      }
    }
    _checkListConstraints(path, value.length, minItems, maxItems);
    return result;
  }

  @override
  List<A> objectList<A>(
    String name,
    Schema<A> itemSchema, {
    int? minItems,
    int? maxItems,
  }) {
    _expect(name, 'array');
    final path = _pathOf(name);
    final value = _input[name];
    if (value == null) {
      errors.add(ValidationError(path, 'is required'));
      return const [];
    }
    if (value is! List) {
      errors.add(ValidationError(path, 'must be an array'));
      return const [];
    }
    final result = <A>[];
    for (var i = 0; i < value.length; i++) {
      final elementPath = '$path[$i]';
      final element = value[i];
      if (element is! Map) {
        errors.add(ValidationError(elementPath, 'must be an object'));
        // Keep the procedure running with a dummy of the right type, rather
        // than stopping the whole list at the first bad element.
        result.add(itemSchema.readWith(Recorder()));
        continue;
      }
      final child = Validator(
        _asStringKeyedMap(element),
        itemSchema.spec,
        coerce: coerce,
        errors: errors,
        path: elementPath,
      );
      result.add(itemSchema.readWith(child));
      child.finish();
    }
    _checkListConstraints(path, value.length, minItems, maxItems);
    return result;
  }

  @override
  List<A>? objectListOrNull<A>(
    String name,
    Schema<A> itemSchema, {
    int? minItems,
    int? maxItems,
  }) {
    _expect(name, 'array');
    final path = _pathOf(name);
    final value = _input[name];
    if (value == null) return null;
    if (value is! List) {
      errors.add(ValidationError(path, 'must be an array'));
      return null;
    }
    final result = <A>[];
    for (var i = 0; i < value.length; i++) {
      final elementPath = '$path[$i]';
      final element = value[i];
      if (element is! Map) {
        errors.add(ValidationError(elementPath, 'must be an object'));
        result.add(itemSchema.readWith(Recorder()));
        continue;
      }
      final child = Validator(
        _asStringKeyedMap(element),
        itemSchema.spec,
        coerce: coerce,
        errors: errors,
        path: elementPath,
      );
      result.add(itemSchema.readWith(child));
      child.finish();
    }
    _checkListConstraints(path, value.length, minItems, maxItems);
    return result;
  }

  @override
  A object<A>(String name, Schema<A> schema) {
    _expect(name, 'object');
    final path = _pathOf(name);
    final value = _input[name];
    if (value == null) {
      errors.add(ValidationError(path, 'is required'));
      // A dummy of type A, so a missing nested object does not stop the
      // rest of the procedure from running and reporting its own errors.
      return schema.readWith(Recorder());
    }
    if (value is! Map) {
      errors.add(ValidationError(path, 'must be an object'));
      return schema.readWith(Recorder());
    }
    final child = Validator(
      _asStringKeyedMap(value),
      schema.spec,
      coerce: coerce,
      errors: errors,
      path: path,
    );
    final result = schema.readWith(child);
    child.finish();
    return result;
  }

  @override
  A? objectOrNull<A>(String name, Schema<A> schema) {
    _expect(name, 'object');
    final path = _pathOf(name);
    final value = _input[name];
    if (value == null) return null;
    if (value is! Map) {
      errors.add(ValidationError(path, 'must be an object'));
      return null;
    }
    final child = Validator(
      _asStringKeyedMap(value),
      schema.spec,
      coerce: coerce,
      errors: errors,
      path: path,
    );
    final result = schema.readWith(child);
    child.finish();
    return result;
  }

  // Delegates to the shared constraint checks in constraints.dart, which
  // Output (the response side) reuses so the two sides never drift apart
  // in wording. Kept as thin wrappers here so every call site above stays
  // unchanged.
  void _checkStringConstraints(
    String path,
    String value,
    int? minLength,
    int? maxLength,
    Pattern? pattern,
  ) => constraints.checkStringConstraints(
    errors,
    path,
    value,
    minLength,
    maxLength,
    pattern,
  );

  void _checkPattern(String path, String value, Pattern? pattern) =>
      constraints.checkPattern(errors, path, value, pattern);

  void _checkNumConstraints(String path, num value, num? min, num? max) =>
      constraints.checkNumConstraints(errors, path, value, min, max);

  void _checkDateTimeBounds(
    String path,
    DateTime value,
    DateTime? min,
    DateTime? max,
  ) => constraints.checkDateTimeBounds(errors, path, value, min, max);

  void _checkListConstraints(
    String path,
    int length,
    int? minItems,
    int? maxItems,
  ) => constraints.checkListConstraints(
    errors,
    path,
    length,
    minItems,
    maxItems,
  );

  String? _asString(Object? value) {
    // Deliberately one-directional: this only ever turns text into a
    // scalar (see [_asInteger] etc.), never the other way around. A
    // caller sharing one schema between a JSON body and a coerced query
    // string would otherwise have `coerce: true` silently turn a JSON
    // `{"name": 34}` into the string "34" instead of the type error it
    // should be — coercion exists for text-only input, not to paper over
    // the wrong JSON type.
    if (value is String) return value;
    return null;
  }

  int? _asInteger(Object? value) {
    if (value is int) return value;
    // A double with nothing after the decimal point — 3.0, not 3.7 — is
    // accepted for an integer field regardless of [coerce]. JSON has one
    // number type, so a client encoding a whole number as a double (common
    // from Python, Dart's own `double` literals, ...) would otherwise get
    // an error it has no way to act on: the value it sent really is the
    // integer the schema asked for.
    if (value is double &&
        value.isFinite &&
        value == value.truncateToDouble()) {
      return value.toInt();
    }
    if (coerce && value is String) return int.tryParse(value);
    return null;
  }

  double? _asNumber(Object? value) {
    final double? number;
    if (value is num) {
      number = value.toDouble();
    } else if (coerce && value is String) {
      number = double.tryParse(value);
    } else {
      return null;
    }
    // double.tryParse accepts 'NaN', 'Infinity' and '-Infinity', and a query
    // string is always coerced, so without this ?price=NaN reached handlers.
    // NaN is also the one value min and max cannot stop: every comparison
    // with it is false, so it slipped past both bounds at once. JSON itself
    // cannot carry these, but parse also takes a map built in code.
    return number != null && number.isFinite ? number : null;
  }

  bool? _asBoolean(Object? value) {
    if (value is bool) return value;
    if (coerce && value is String) {
      if (value == 'true' || value == '1') return true;
      if (value == 'false' || value == '0') return false;
    }
    return null;
  }

  // Represented as a string in JSON either way, so parsing it does not
  // depend on [coerce] — that flag is about a scalar standing in for
  // another scalar, not about how dates are written.
  DateTime? _asDateTime(Object? value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  // coerce has no effect here, and that's safe rather than an oversight.
  // Matching goes through [_asString], which — since removing the
  // num/bool-to-string direction above — only ever returns a value that
  // was already a String. So a bool or a num given for an enum field is
  // rejected outright, with or without coerce: there is no text
  // representation of `true` or `34` that [_asString] will produce for
  // coerce to have turned into a candidate name in the first place.
  T? _asEnumValue<T extends Enum>(Object? value, List<T> values) {
    final name = _asString(value);
    if (name == null) return null;
    for (final candidate in values) {
      if (candidate.name == name) return candidate;
    }
    return null;
  }

  Map<String, Object?> _asStringKeyedMap(Map value) =>
      value.map((key, v) => MapEntry(key.toString(), v));
}

final _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
