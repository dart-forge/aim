import 'package:aim_schema/src/errors.dart';
import 'package:aim_schema/src/field_spec.dart';
import 'package:aim_schema/src/reader.dart';
import 'package:aim_schema/src/schema.dart';

/// Collects what a schema asks for.
///
/// Returns dummy values, which is why a schema may not branch on what it
/// reads: there is nothing real to branch on during this pass.
final class Recorder implements Reader {
  /// The fields asked for so far, in the order they were asked for.
  final fields = <FieldSpec>[];

  @override
  String string(
    String name, {
    int? minLength,
    int? maxLength,
    Pattern? pattern,
  }) {
    fields.add(
      FieldSpec(
        name,
        'string',
        minLength: minLength,
        maxLength: maxLength,
        pattern: pattern,
      ),
    );
    return '';
  }

  @override
  int integer(String name, {int? min, int? max}) {
    fields.add(FieldSpec(name, 'integer', min: min, max: max));
    return 0;
  }

  @override
  double number(String name, {double? min, double? max}) {
    fields.add(FieldSpec(name, 'number', min: min, max: max));
    return 0;
  }

  @override
  bool boolean(String name) {
    fields.add(FieldSpec(name, 'boolean'));
    return false;
  }

  @override
  DateTime dateTime(String name, {DateTime? min, DateTime? max}) {
    fields.add(
      FieldSpec(
        name,
        'string',
        format: 'date-time',
        minDateTime: min,
        maxDateTime: max,
      ),
    );
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  @override
  String? stringOrNull(
    String name, {
    int? minLength,
    int? maxLength,
    Pattern? pattern,
  }) {
    fields.add(
      FieldSpec(
        name,
        'string',
        required: false,
        minLength: minLength,
        maxLength: maxLength,
        pattern: pattern,
      ),
    );
    return null;
  }

  @override
  int? integerOrNull(String name, {int? min, int? max}) {
    fields.add(FieldSpec(name, 'integer', required: false, min: min, max: max));
    return null;
  }

  @override
  double? numberOrNull(String name, {double? min, double? max}) {
    fields.add(FieldSpec(name, 'number', required: false, min: min, max: max));
    return null;
  }

  @override
  bool? booleanOrNull(String name) {
    fields.add(FieldSpec(name, 'boolean', required: false));
    return null;
  }

  @override
  DateTime? dateTimeOrNull(String name, {DateTime? min, DateTime? max}) {
    fields.add(
      FieldSpec(
        name,
        'string',
        required: false,
        format: 'date-time',
        minDateTime: min,
        maxDateTime: max,
      ),
    );
    return null;
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
    fields.add(
      FieldSpec(
        name,
        'string',
        format: 'enum',
        values: [for (final v in values) v.name],
      ),
    );
    return values.first;
  }

  @override
  T? enumValueOrNull<T extends Enum>(String name, List<T> values) {
    fields.add(
      FieldSpec(
        name,
        'string',
        required: false,
        format: 'enum',
        values: [for (final v in values) v.name],
      ),
    );
    return null;
  }

  @override
  List<String> stringList(
    String name, {
    int? minItems,
    int? maxItems,
    Pattern? pattern,
  }) {
    fields.add(
      FieldSpec(
        name,
        'array',
        itemType: 'string',
        minItems: minItems,
        maxItems: maxItems,
        pattern: pattern,
      ),
    );
    return const [];
  }

  @override
  List<String>? stringListOrNull(
    String name, {
    int? minItems,
    int? maxItems,
    Pattern? pattern,
  }) {
    fields.add(
      FieldSpec(
        name,
        'array',
        required: false,
        itemType: 'string',
        minItems: minItems,
        maxItems: maxItems,
        pattern: pattern,
      ),
    );
    return null;
  }

  @override
  List<int> integerList(String name, {int? minItems, int? maxItems}) {
    fields.add(
      FieldSpec(
        name,
        'array',
        itemType: 'integer',
        minItems: minItems,
        maxItems: maxItems,
      ),
    );
    return const [];
  }

  @override
  List<int>? integerListOrNull(String name, {int? minItems, int? maxItems}) {
    fields.add(
      FieldSpec(
        name,
        'array',
        required: false,
        itemType: 'integer',
        minItems: minItems,
        maxItems: maxItems,
      ),
    );
    return null;
  }

  @override
  List<double> numberList(String name, {int? minItems, int? maxItems}) {
    fields.add(
      FieldSpec(
        name,
        'array',
        itemType: 'number',
        minItems: minItems,
        maxItems: maxItems,
      ),
    );
    return const [];
  }

  @override
  List<double>? numberListOrNull(String name, {int? minItems, int? maxItems}) {
    fields.add(
      FieldSpec(
        name,
        'array',
        required: false,
        itemType: 'number',
        minItems: minItems,
        maxItems: maxItems,
      ),
    );
    return null;
  }

  @override
  List<bool> booleanList(String name, {int? minItems, int? maxItems}) {
    fields.add(
      FieldSpec(
        name,
        'array',
        itemType: 'boolean',
        minItems: minItems,
        maxItems: maxItems,
      ),
    );
    return const [];
  }

  @override
  List<bool>? booleanListOrNull(String name, {int? minItems, int? maxItems}) {
    fields.add(
      FieldSpec(
        name,
        'array',
        required: false,
        itemType: 'boolean',
        minItems: minItems,
        maxItems: maxItems,
      ),
    );
    return null;
  }

  @override
  List<DateTime> dateTimeList(
    String name, {
    int? minItems,
    int? maxItems,
    DateTime? min,
    DateTime? max,
  }) {
    fields.add(
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
    );
    return const [];
  }

  @override
  List<DateTime>? dateTimeListOrNull(
    String name, {
    int? minItems,
    int? maxItems,
    DateTime? min,
    DateTime? max,
  }) {
    fields.add(
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
    );
    return null;
  }

  @override
  List<T> enumList<T extends Enum>(
    String name,
    List<T> values, {
    int? minItems,
    int? maxItems,
  }) {
    fields.add(
      FieldSpec(
        name,
        'array',
        itemType: 'string',
        format: 'enum',
        values: [for (final v in values) v.name],
        minItems: minItems,
        maxItems: maxItems,
      ),
    );
    return const [];
  }

  @override
  List<T>? enumListOrNull<T extends Enum>(
    String name,
    List<T> values, {
    int? minItems,
    int? maxItems,
  }) {
    fields.add(
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
    );
    return null;
  }

  @override
  List<A> objectList<A>(
    String name,
    Schema<A> itemSchema, {
    int? minItems,
    int? maxItems,
  }) {
    fields.add(
      FieldSpec(
        name,
        'array',
        itemType: 'object',
        nested: itemSchema.spec,
        minItems: minItems,
        maxItems: maxItems,
      ),
    );
    return const [];
  }

  @override
  List<A>? objectListOrNull<A>(
    String name,
    Schema<A> itemSchema, {
    int? minItems,
    int? maxItems,
  }) {
    fields.add(
      FieldSpec(
        name,
        'array',
        required: false,
        itemType: 'object',
        nested: itemSchema.spec,
        minItems: minItems,
        maxItems: maxItems,
      ),
    );
    return null;
  }

  @override
  A object<A>(String name, Schema<A> schema) {
    fields.add(FieldSpec(name, 'object', nested: schema.spec));
    // A dummy of type A is manufactured by running the nested schema's own
    // procedure through a fresh Recorder, rather than trying to construct
    // one directly — A is arbitrary and this file has no other way to make
    // one.
    return schema.readWith(Recorder());
  }

  @override
  A? objectOrNull<A>(String name, Schema<A> schema) {
    fields.add(FieldSpec(name, 'object', required: false, nested: schema.spec));
    return null;
  }
}
