import 'package:aim_schema/src/constraints.dart' as constraints;
import 'package:aim_schema/src/errors.dart';
import 'package:aim_schema/src/field_spec.dart';

/// One field an [Output] writes, as built by [Writer].
///
/// The write-side counterpart of a [Reader] method's result: instead of
/// returning a value, it takes one (through the getter it was built with)
/// and appends it — plus any constraint violations — into the JSON object
/// under construction.
final class OutputField<T> {
  OutputField(this.spec, this._write);

  /// The same [FieldSpec] shape [Schema]'s recorder would produce for the
  /// equivalent [Reader] call, so [Output.toJsonSchema] matches.
  final FieldSpec spec;

  final void Function(
    T value,
    String path,
    Map<String, Object?> into,
    List<ValidationError> errors,
  )
  _write;

  /// Reads this field's value out of [value] via the getter it was built
  /// with, writes it into [into] under [spec.name], and appends any
  /// constraint violation to [errors] under [path].
  void write(
    T value,
    String path,
    Map<String, Object?> into,
    List<ValidationError> errors,
  ) => _write(value, path, into, errors);
}

/// Builds the [OutputField]s of one [Output], mirroring [Reader]'s method
/// names and constraint parameters exactly, but for writing a value instead
/// of reading one.
///
/// Every scalar type has the same four forms as [Reader] — required,
/// nullable, list, nullable list — plus [object] and its three siblings for
/// nesting another [Output]. See [Reader] for the full table; the same
/// shape applies here.
final class Writer<T> {
  Writer._();

  OutputField<T> string(
    String name,
    String Function(T) get, {
    int? minLength,
    int? maxLength,
    Pattern? pattern,
  }) => OutputField(
    FieldSpec(
      name,
      'string',
      minLength: minLength,
      maxLength: maxLength,
      pattern: pattern,
    ),
    (value, path, into, errors) {
      final v = get(value);
      into[name] = v;
      constraints.checkStringConstraints(
        errors,
        path,
        v,
        minLength,
        maxLength,
        pattern,
      );
    },
  );

  OutputField<T> stringOrNull(
    String name,
    String? Function(T) get, {
    int? minLength,
    int? maxLength,
    Pattern? pattern,
  }) => OutputField(
    FieldSpec(
      name,
      'string',
      required: false,
      minLength: minLength,
      maxLength: maxLength,
      pattern: pattern,
    ),
    (value, path, into, errors) {
      final v = get(value);
      if (v == null) {
        into[name] = null;
        return;
      }
      into[name] = v;
      constraints.checkStringConstraints(
        errors,
        path,
        v,
        minLength,
        maxLength,
        pattern,
      );
    },
  );

  OutputField<T> stringList(
    String name,
    List<String> Function(T) get, {
    int? minItems,
    int? maxItems,
    Pattern? pattern,
  }) => OutputField(
    FieldSpec(
      name,
      'array',
      itemType: 'string',
      minItems: minItems,
      maxItems: maxItems,
      pattern: pattern,
    ),
    (value, path, into, errors) {
      final list = get(value);
      into[name] = List<Object?>.of(list);
      for (var i = 0; i < list.length; i++) {
        constraints.checkPattern(errors, '$path[$i]', list[i], pattern);
      }
      constraints.checkListConstraints(
        errors,
        path,
        list.length,
        minItems,
        maxItems,
      );
    },
  );

  OutputField<T> stringListOrNull(
    String name,
    List<String>? Function(T) get, {
    int? minItems,
    int? maxItems,
    Pattern? pattern,
  }) => OutputField(
    FieldSpec(
      name,
      'array',
      required: false,
      itemType: 'string',
      minItems: minItems,
      maxItems: maxItems,
      pattern: pattern,
    ),
    (value, path, into, errors) {
      final list = get(value);
      if (list == null) {
        into[name] = null;
        return;
      }
      into[name] = List<Object?>.of(list);
      for (var i = 0; i < list.length; i++) {
        constraints.checkPattern(errors, '$path[$i]', list[i], pattern);
      }
      constraints.checkListConstraints(
        errors,
        path,
        list.length,
        minItems,
        maxItems,
      );
    },
  );

  OutputField<T> integer(
    String name,
    int Function(T) get, {
    int? min,
    int? max,
  }) => OutputField(FieldSpec(name, 'integer', min: min, max: max), (
    value,
    path,
    into,
    errors,
  ) {
    final v = get(value);
    into[name] = v;
    constraints.checkNumConstraints(errors, path, v, min, max);
  });

  OutputField<T> integerOrNull(
    String name,
    int? Function(T) get, {
    int? min,
    int? max,
  }) => OutputField(
    FieldSpec(name, 'integer', required: false, min: min, max: max),
    (value, path, into, errors) {
      final v = get(value);
      if (v == null) {
        into[name] = null;
        return;
      }
      into[name] = v;
      constraints.checkNumConstraints(errors, path, v, min, max);
    },
  );

  OutputField<T> integerList(
    String name,
    List<int> Function(T) get, {
    int? minItems,
    int? maxItems,
  }) => OutputField(
    FieldSpec(
      name,
      'array',
      itemType: 'integer',
      minItems: minItems,
      maxItems: maxItems,
    ),
    (value, path, into, errors) {
      final list = get(value);
      into[name] = List<Object?>.of(list);
      constraints.checkListConstraints(
        errors,
        path,
        list.length,
        minItems,
        maxItems,
      );
    },
  );

  OutputField<T> integerListOrNull(
    String name,
    List<int>? Function(T) get, {
    int? minItems,
    int? maxItems,
  }) => OutputField(
    FieldSpec(
      name,
      'array',
      required: false,
      itemType: 'integer',
      minItems: minItems,
      maxItems: maxItems,
    ),
    (value, path, into, errors) {
      final list = get(value);
      if (list == null) {
        into[name] = null;
        return;
      }
      into[name] = List<Object?>.of(list);
      constraints.checkListConstraints(
        errors,
        path,
        list.length,
        minItems,
        maxItems,
      );
    },
  );

  OutputField<T> number(
    String name,
    double Function(T) get, {
    double? min,
    double? max,
  }) => OutputField(FieldSpec(name, 'number', min: min, max: max), (
    value,
    path,
    into,
    errors,
  ) {
    final v = get(value);
    into[name] = v;
    _checkFinite(errors, path, v);
    constraints.checkNumConstraints(errors, path, v, min, max);
  });

  OutputField<T> numberOrNull(
    String name,
    double? Function(T) get, {
    double? min,
    double? max,
  }) => OutputField(
    FieldSpec(name, 'number', required: false, min: min, max: max),
    (value, path, into, errors) {
      final v = get(value);
      if (v == null) {
        into[name] = null;
        return;
      }
      into[name] = v;
      _checkFinite(errors, path, v);
      constraints.checkNumConstraints(errors, path, v, min, max);
    },
  );

  OutputField<T> numberList(
    String name,
    List<double> Function(T) get, {
    int? minItems,
    int? maxItems,
  }) => OutputField(
    FieldSpec(
      name,
      'array',
      itemType: 'number',
      minItems: minItems,
      maxItems: maxItems,
    ),
    (value, path, into, errors) {
      final list = get(value);
      into[name] = List<Object?>.of(list);
      for (var i = 0; i < list.length; i++) {
        _checkFinite(errors, '$path[$i]', list[i]);
      }
      constraints.checkListConstraints(
        errors,
        path,
        list.length,
        minItems,
        maxItems,
      );
    },
  );

  OutputField<T> numberListOrNull(
    String name,
    List<double>? Function(T) get, {
    int? minItems,
    int? maxItems,
  }) => OutputField(
    FieldSpec(
      name,
      'array',
      required: false,
      itemType: 'number',
      minItems: minItems,
      maxItems: maxItems,
    ),
    (value, path, into, errors) {
      final list = get(value);
      if (list == null) {
        into[name] = null;
        return;
      }
      into[name] = List<Object?>.of(list);
      for (var i = 0; i < list.length; i++) {
        _checkFinite(errors, '$path[$i]', list[i]);
      }
      constraints.checkListConstraints(
        errors,
        path,
        list.length,
        minItems,
        maxItems,
      );
    },
  );

  OutputField<T> boolean(String name, bool Function(T) get) =>
      OutputField(FieldSpec(name, 'boolean'), (value, path, into, errors) {
        into[name] = get(value);
      });

  OutputField<T> booleanOrNull(String name, bool? Function(T) get) =>
      OutputField(FieldSpec(name, 'boolean', required: false), (
        value,
        path,
        into,
        errors,
      ) {
        into[name] = get(value);
      });

  OutputField<T> booleanList(
    String name,
    List<bool> Function(T) get, {
    int? minItems,
    int? maxItems,
  }) => OutputField(
    FieldSpec(
      name,
      'array',
      itemType: 'boolean',
      minItems: minItems,
      maxItems: maxItems,
    ),
    (value, path, into, errors) {
      final list = get(value);
      into[name] = List<Object?>.of(list);
      constraints.checkListConstraints(
        errors,
        path,
        list.length,
        minItems,
        maxItems,
      );
    },
  );

  OutputField<T> booleanListOrNull(
    String name,
    List<bool>? Function(T) get, {
    int? minItems,
    int? maxItems,
  }) => OutputField(
    FieldSpec(
      name,
      'array',
      required: false,
      itemType: 'boolean',
      minItems: minItems,
      maxItems: maxItems,
    ),
    (value, path, into, errors) {
      final list = get(value);
      if (list == null) {
        into[name] = null;
        return;
      }
      into[name] = List<Object?>.of(list);
      constraints.checkListConstraints(
        errors,
        path,
        list.length,
        minItems,
        maxItems,
      );
    },
  );

  OutputField<T> dateTime(
    String name,
    DateTime Function(T) get, {
    DateTime? min,
    DateTime? max,
  }) => OutputField(
    FieldSpec(
      name,
      'string',
      format: 'date-time',
      minDateTime: min,
      maxDateTime: max,
    ),
    (value, path, into, errors) {
      final v = get(value);
      into[name] = v.toIso8601String();
      constraints.checkDateTimeBounds(errors, path, v, min, max);
    },
  );

  OutputField<T> dateTimeOrNull(
    String name,
    DateTime? Function(T) get, {
    DateTime? min,
    DateTime? max,
  }) => OutputField(
    FieldSpec(
      name,
      'string',
      required: false,
      format: 'date-time',
      minDateTime: min,
      maxDateTime: max,
    ),
    (value, path, into, errors) {
      final v = get(value);
      if (v == null) {
        into[name] = null;
        return;
      }
      into[name] = v.toIso8601String();
      constraints.checkDateTimeBounds(errors, path, v, min, max);
    },
  );

  OutputField<T> dateTimeList(
    String name,
    List<DateTime> Function(T) get, {
    int? minItems,
    int? maxItems,
    DateTime? min,
    DateTime? max,
  }) => OutputField(
    FieldSpec(
      name,
      'array',
      itemType: 'string',
      format: 'date-time',
      minDateTime: min,
      maxDateTime: max,
      minItems: minItems,
      maxItems: maxItems,
    ),
    (value, path, into, errors) {
      final list = get(value);
      into[name] = [for (final v in list) v.toIso8601String()];
      for (var i = 0; i < list.length; i++) {
        constraints.checkDateTimeBounds(errors, '$path[$i]', list[i], min, max);
      }
      constraints.checkListConstraints(
        errors,
        path,
        list.length,
        minItems,
        maxItems,
      );
    },
  );

  OutputField<T> dateTimeListOrNull(
    String name,
    List<DateTime>? Function(T) get, {
    int? minItems,
    int? maxItems,
    DateTime? min,
    DateTime? max,
  }) => OutputField(
    FieldSpec(
      name,
      'array',
      required: false,
      itemType: 'string',
      format: 'date-time',
      minDateTime: min,
      maxDateTime: max,
      minItems: minItems,
      maxItems: maxItems,
    ),
    (value, path, into, errors) {
      final list = get(value);
      if (list == null) {
        into[name] = null;
        return;
      }
      into[name] = [for (final v in list) v.toIso8601String()];
      for (var i = 0; i < list.length; i++) {
        constraints.checkDateTimeBounds(errors, '$path[$i]', list[i], min, max);
      }
      constraints.checkListConstraints(
        errors,
        path,
        list.length,
        minItems,
        maxItems,
      );
    },
  );

  OutputField<T> enumValue<V extends Enum>(
    String name,
    V Function(T) get,
    List<V> values,
  ) => OutputField(
    FieldSpec(
      name,
      'string',
      format: 'enum',
      values: [for (final v in values) v.name],
    ),
    (value, path, into, errors) {
      final v = get(value);
      into[name] = v.name;
      if (!values.contains(v)) {
        errors.add(
          ValidationError(path, constraints.mustBeOneOfMessage(values)),
        );
      }
    },
  );

  OutputField<T> enumValueOrNull<V extends Enum>(
    String name,
    V? Function(T) get,
    List<V> values,
  ) => OutputField(
    FieldSpec(
      name,
      'string',
      required: false,
      format: 'enum',
      values: [for (final v in values) v.name],
    ),
    (value, path, into, errors) {
      final v = get(value);
      if (v == null) {
        into[name] = null;
        return;
      }
      into[name] = v.name;
      if (!values.contains(v)) {
        errors.add(
          ValidationError(path, constraints.mustBeOneOfMessage(values)),
        );
      }
    },
  );

  OutputField<T> enumList<V extends Enum>(
    String name,
    List<V> Function(T) get,
    List<V> values, {
    int? minItems,
    int? maxItems,
  }) => OutputField(
    FieldSpec(
      name,
      'array',
      itemType: 'string',
      format: 'enum',
      values: [for (final v in values) v.name],
      minItems: minItems,
      maxItems: maxItems,
    ),
    (value, path, into, errors) {
      final list = get(value);
      into[name] = [for (final v in list) v.name];
      for (var i = 0; i < list.length; i++) {
        if (!values.contains(list[i])) {
          errors.add(
            ValidationError(
              '$path[$i]',
              constraints.mustBeOneOfMessage(values),
            ),
          );
        }
      }
      constraints.checkListConstraints(
        errors,
        path,
        list.length,
        minItems,
        maxItems,
      );
    },
  );

  OutputField<T> enumListOrNull<V extends Enum>(
    String name,
    List<V>? Function(T) get,
    List<V> values, {
    int? minItems,
    int? maxItems,
  }) => OutputField(
    FieldSpec(
      name,
      'array',
      required: false,
      itemType: 'string',
      format: 'enum',
      values: [for (final v in values) v.name],
      minItems: minItems,
      maxItems: maxItems,
    ),
    (value, path, into, errors) {
      final list = get(value);
      if (list == null) {
        into[name] = null;
        return;
      }
      into[name] = [for (final v in list) v.name];
      for (var i = 0; i < list.length; i++) {
        if (!values.contains(list[i])) {
          errors.add(
            ValidationError(
              '$path[$i]',
              constraints.mustBeOneOfMessage(values),
            ),
          );
        }
      }
      constraints.checkListConstraints(
        errors,
        path,
        list.length,
        minItems,
        maxItems,
      );
    },
  );

  OutputField<T> object<V>(String name, V Function(T) get, Output<V> output) =>
      OutputField(FieldSpec(name, 'object', nested: output.spec), (
        value,
        path,
        into,
        errors,
      ) {
        final v = get(value);
        final nested = <String, Object?>{};
        output._writeInto(v, path, nested, errors);
        into[name] = nested;
      });

  OutputField<T> objectOrNull<V>(
    String name,
    V? Function(T) get,
    Output<V> output,
  ) => OutputField(
    FieldSpec(name, 'object', required: false, nested: output.spec),
    (value, path, into, errors) {
      final v = get(value);
      if (v == null) {
        into[name] = null;
        return;
      }
      final nested = <String, Object?>{};
      output._writeInto(v, path, nested, errors);
      into[name] = nested;
    },
  );

  OutputField<T> objectList<V>(
    String name,
    List<V> Function(T) get,
    Output<V> output, {
    int? minItems,
    int? maxItems,
  }) => OutputField(
    FieldSpec(
      name,
      'array',
      itemType: 'object',
      nested: output.spec,
      minItems: minItems,
      maxItems: maxItems,
    ),
    (value, path, into, errors) {
      final list = get(value);
      final result = <Object?>[];
      for (var i = 0; i < list.length; i++) {
        final elementPath = '$path[$i]';
        final nested = <String, Object?>{};
        output._writeInto(list[i], elementPath, nested, errors);
        result.add(nested);
      }
      into[name] = result;
      constraints.checkListConstraints(
        errors,
        path,
        list.length,
        minItems,
        maxItems,
      );
    },
  );

  OutputField<T> objectListOrNull<V>(
    String name,
    List<V>? Function(T) get,
    Output<V> output, {
    int? minItems,
    int? maxItems,
  }) => OutputField(
    FieldSpec(
      name,
      'array',
      required: false,
      itemType: 'object',
      nested: output.spec,
      minItems: minItems,
      maxItems: maxItems,
    ),
    (value, path, into, errors) {
      final list = get(value);
      if (list == null) {
        into[name] = null;
        return;
      }
      final result = <Object?>[];
      for (var i = 0; i < list.length; i++) {
        final elementPath = '$path[$i]';
        final nested = <String, Object?>{};
        output._writeInto(list[i], elementPath, nested, errors);
        result.add(nested);
      }
      into[name] = result;
      constraints.checkListConstraints(
        errors,
        path,
        list.length,
        minItems,
        maxItems,
      );
    },
  );
}

void _checkFinite(List<ValidationError> errors, String path, double value) {
  if (!value.isFinite) {
    errors.add(ValidationError(path, 'must be a finite number'));
  }
}

/// A write-only field list that encodes a value of type [T] to
/// JSON-ready values while collecting constraint violations, the response
/// counterpart of [Schema].
///
/// ```dart
/// final userOut = Output<User>((w) => [
///       w.integer('id', (u) => u.id, min: 1),
///       w.string('name', (u) => u.name, maxLength: 80),
///     ]);
///
/// final json = userOut.encode(user); // throws ResponseValidationException
/// ```
///
/// [build] runs once, eagerly, when the [Output] is constructed — the same
/// as [Schema]'s recording pass runs once and is cached, except here there
/// is no separate recording step: a [Writer] method both describes the
/// field (its [FieldSpec]) and builds the closure that will later write it,
/// in the same call.
final class Output<T> {
  Output(List<OutputField<T>> Function(Writer<T> w) build)
    : _fields = _checkedFields(build(Writer<T>._()));

  static List<OutputField<T>> _checkedFields<T>(List<OutputField<T>> fields) {
    final seen = <String>{};
    for (final field in fields) {
      if (!seen.add(field.spec.name)) {
        throw ArgumentError.value(
          field.spec.name,
          'name',
          'Output already has a field named "${field.spec.name}"',
        );
      }
    }
    return fields;
  }

  final List<OutputField<T>> _fields;

  /// What this [Output] writes. The same [FieldSpec] shape [Schema.spec]
  /// produces for the equivalent [Reader] calls.
  List<FieldSpec> get spec => [for (final field in _fields) field.spec];

  /// A JSON Schema description of the same declaration, in the same shape
  /// as [Schema.toJsonSchema].
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

  /// Encodes [value] to JSON-ready values.
  ///
  /// Throws [ResponseValidationException], carrying every violation found
  /// rather than just the first, if [value] does not match this
  /// declaration.
  Map<String, Object?> encode(T value) {
    final errors = <ValidationError>[];
    final result = <String, Object?>{};
    _writeInto(value, '', result, errors);
    if (errors.isNotEmpty) throw ResponseValidationException(errors);
    return result;
  }

  /// Writes [value]'s fields into [into], appending violations to [errors]
  /// with paths rooted at [path] — `''` at the top level, `name` (then
  /// `name.field`, `name[i]`, ...) when called from a nested [object] or
  /// [objectList] field.
  void _writeInto(
    T value,
    String path,
    Map<String, Object?> into,
    List<ValidationError> errors,
  ) {
    for (final field in _fields) {
      final fieldPath = path.isEmpty
          ? field.spec.name
          : '$path.${field.spec.name}';
      field.write(value, fieldPath, into, errors);
    }
  }
}
