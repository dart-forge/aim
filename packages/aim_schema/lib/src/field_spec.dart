/// One field, as the recording pass saw it.
///
/// This is the material behind [Schema.toJsonSchema] and the determinism
/// check in the validating reader: it is what a schema asked for, without
/// the values a real request would have supplied.
final class FieldSpec {
  const FieldSpec(
    this.name,
    this.type, {
    this.required = true,
    this.minLength,
    this.maxLength,
    this.pattern,
    this.min,
    this.max,
    this.minDateTime,
    this.maxDateTime,
    this.minItems,
    this.maxItems,
    this.values,
    this.format,
    this.nested,
    this.itemType,
  });

  /// The field's name, as passed to the [Reader] method that produced it.
  final String name;

  /// A JSON Schema type name: `'string'`, `'integer'`, `'number'`,
  /// `'boolean'`, `'array'`, `'object'`.
  final String type;

  /// Whether a request must supply this field.
  final bool required;

  final int? minLength;
  final int? maxLength;

  /// A pattern a string value must contain a match of.
  ///
  /// For `type == 'array'` with a string item, this is the pattern each
  /// element must match instead — [Reader.string]'s family reuses this same
  /// field for the array forms, the way [minItems]/[maxItems] are the only
  /// fields that ever describe the array itself rather than its items.
  final Pattern? pattern;

  final num? min;
  final num? max;

  /// A `DateTime` an item must be at or after / at or before.
  ///
  /// Reused for `type == 'array'` the same way [pattern] is: it describes
  /// each element, not the array.
  final DateTime? minDateTime;
  final DateTime? maxDateTime;

  final int? minItems;
  final int? maxItems;

  /// For an enum field, the allowed values, as each constant's `Enum.name`.
  ///
  /// For `type == 'array'`, the allowed values for each element instead.
  final List<String>? values;

  /// A discriminator between fields [Reader] otherwise records identically.
  ///
  /// A plain string, a `dateTime` (read as an ISO 8601 string), and an
  /// `enumValue` (matched by `Enum.name`) are all recorded with [type]
  /// `'string'` — there is no other JSON Schema type for any of them. This
  /// carries `'date-time'`, `'enum'`, or `null` (a plain string) so the
  /// validating reader's determinism check can tell them apart even though
  /// [type] alone would not; see [Schema.parse]. For `type == 'array'`, it
  /// distinguishes a `stringList` from a `dateTimeList` or an `enumList` the
  /// same way.
  ///
  /// Only `'date-time'` is also a real JSON Schema `format` keyword —
  /// [toJsonSchema] forwards it to the output; `'enum'` is internal and
  /// never appears there (the `enum` keyword, built from [values], already
  /// says that on its own).
  final String? format;

  /// For `'object'`, the nested fields. For an `'array'` of objects, the
  /// item's fields.
  final List<FieldSpec>? nested;

  /// For `'array'`, the item's type name.
  final String? itemType;

  /// This field's own JSON Schema description.
  ///
  /// Does not include `required` — whether a field is required is reported
  /// at the containing object's level, in its `required` list, which is why
  /// this method takes no part in producing one.
  Map<String, Object?> toJsonSchema() {
    final schema = <String, Object?>{'type': type};
    if (type != 'array') {
      if (minLength != null) schema['minLength'] = minLength;
      if (maxLength != null) schema['maxLength'] = maxLength;
      if (pattern != null) schema['pattern'] = _patternText(pattern!);
      if (min != null) schema['minimum'] = min;
      if (max != null) schema['maximum'] = max;
      if (values != null) schema['enum'] = values;
      if (format == 'date-time') schema['format'] = format;
      if (minDateTime != null) {
        schema['formatMinimum'] = minDateTime!.toIso8601String();
      }
      if (maxDateTime != null) {
        schema['formatMaximum'] = maxDateTime!.toIso8601String();
      }
    }
    if (minItems != null) schema['minItems'] = minItems;
    if (maxItems != null) schema['maxItems'] = maxItems;

    final nestedFields = nested;
    if (type == 'object' && nestedFields != null) {
      schema['properties'] = {
        for (final field in nestedFields) field.name: field.toJsonSchema(),
      };
      final nestedRequired = [
        for (final field in nestedFields)
          if (field.required) field.name,
      ];
      if (nestedRequired.isNotEmpty) schema['required'] = nestedRequired;
    }

    final item = itemType;
    if (type == 'array' && item != null) {
      // An item spec built from this field's own item-level constraints —
      // [pattern], [values], [format], [minDateTime], [maxDateTime] — the
      // same reuse described on those fields' doc comments. A nested object
      // item already has its own fields in [nested] instead.
      schema['items'] = nestedFields != null
          ? FieldSpec('', item, nested: nestedFields).toJsonSchema()
          : FieldSpec(
              '',
              item,
              pattern: pattern,
              values: values,
              format: format,
              minDateTime: minDateTime,
              maxDateTime: maxDateTime,
            ).toJsonSchema();
    }

    return schema;
  }
}

String _patternText(Pattern pattern) =>
    pattern is RegExp ? pattern.pattern : pattern.toString();
