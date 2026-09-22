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
    this.min,
    this.max,
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
  final num? min;
  final num? max;
  final int? minItems;
  final int? maxItems;

  /// For an enum field, the allowed values, as each constant's [Enum.name].
  final List<String>? values;

  /// A JSON Schema `format` keyword, e.g. `'date-time'` for a [DateTime]
  /// field, which is otherwise typed `'string'`.
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
    if (minLength != null) schema['minLength'] = minLength;
    if (maxLength != null) schema['maxLength'] = maxLength;
    if (min != null) schema['minimum'] = min;
    if (max != null) schema['maximum'] = max;
    if (minItems != null) schema['minItems'] = minItems;
    if (maxItems != null) schema['maxItems'] = maxItems;
    if (values != null) schema['enum'] = values;
    if (format != null) schema['format'] = format;

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
      schema['items'] = nestedFields == null
          ? {'type': item}
          : FieldSpec('', item, nested: nestedFields).toJsonSchema();
    }

    return schema;
  }
}
