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
  /// Only the name and the type are compared. The constraint values come
  /// from the recording pass, so a constraint computed from a value would
  /// describe one bound and enforce another — documented, not guarded.
  void _expect(String name, String type) {
    final mismatched =
        _index >= _spec.length ||
        _spec[_index].name != name ||
        _spec[_index].type != type;
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
  String string(String name, {int? minLength, int? maxLength}) {
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
    _checkStringConstraints(path, resolved, minLength, maxLength);
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
  DateTime dateTime(String name) {
    _expect(name, 'string');
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
    return resolved;
  }

  @override
  String? stringOrNull(String name, {int? minLength, int? maxLength}) {
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
    _checkStringConstraints(path, resolved, minLength, maxLength);
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
  DateTime? dateTimeOrNull(String name) {
    _expect(name, 'string');
    final path = _pathOf(name);
    final value = _input[name];
    if (value == null) return null;
    final resolved = _asDateTime(value);
    if (resolved == null) {
      errors.add(ValidationError(path, 'must be an ISO 8601 date-time'));
      return null;
    }
    return resolved;
  }

  @override
  T enumValue<T extends Enum>(String name, List<T> values) {
    _expect(name, 'string');
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
    _expect(name, 'string');
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
  List<String> stringList(String name, {int? minItems, int? maxItems}) {
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
      final resolved = _asString(value[i]);
      if (resolved == null) {
        errors.add(ValidationError('$path[$i]', 'must be a string'));
      } else {
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

  void _checkStringConstraints(
    String path,
    String value,
    int? minLength,
    int? maxLength,
  ) {
    if (minLength != null && value.length < minLength) {
      errors.add(
        ValidationError(path, 'must be at least $minLength characters'),
      );
    }
    if (maxLength != null && value.length > maxLength) {
      errors.add(
        ValidationError(path, 'must be at most $maxLength characters'),
      );
    }
  }

  void _checkNumConstraints(String path, num value, num? min, num? max) {
    if (min != null && value < min) {
      errors.add(ValidationError(path, 'must be at least $min'));
    }
    if (max != null && value > max) {
      errors.add(ValidationError(path, 'must be at most $max'));
    }
  }

  void _checkListConstraints(
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

  String? _asString(Object? value) {
    if (value is String) return value;
    if (coerce && (value is num || value is bool)) return value.toString();
    return null;
  }

  int? _asInteger(Object? value) {
    if (value is int) return value;
    if (coerce && value is String) return int.tryParse(value);
    return null;
  }

  double? _asNumber(Object? value) {
    if (value is num) return value.toDouble();
    if (coerce && value is String) return double.tryParse(value);
    return null;
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
