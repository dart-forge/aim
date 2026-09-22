import 'package:aim_schema/src/errors.dart';
import 'package:aim_schema/src/field_spec.dart';
import 'package:aim_schema/src/reader.dart';

/// Validates real input against what the recording pass saw, and returns
/// the values with static types.
///
/// Every method starts by checking the procedure is asking for what it
/// asked for while recording — see [_expect]. That check is what makes it
/// safe for a schema's procedure to run twice with two different meanings.
final class Validator implements Reader {
  Validator(this._input, this._spec, {required this.coerce, this._path = ''});

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
  final errors = <ValidationError>[];

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
    if (min != null && resolved < min) {
      errors.add(ValidationError(path, 'must be at least $min'));
    }
    if (max != null && resolved > max) {
      errors.add(ValidationError(path, 'must be at most $max'));
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
}
