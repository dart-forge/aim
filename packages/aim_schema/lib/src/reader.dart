import 'package:aim_schema/src/schema.dart';

/// Reads one field at a time from request data.
///
/// A schema is a procedure written against this interface. The same
/// procedure is run twice over: once to record what it asks for (which is
/// what `Schema.toJsonSchema` reports) and once per request to validate and
/// return the values.
///
/// **The procedure must ask for the same fields every time.** It cannot
/// branch on a value it has read, because the recording pass has no values
/// to give it. Doing so throws a [StateError] rather than quietly
/// describing one shape and validating another.
///
/// This is declared as an `abstract interface class` so a third party could
/// in principle implement it — for instance to interpret a schema against
/// something other than a `Map<String, Object?>`. That is not, however, a
/// use this package designs for or keeps stable: every scalar type here has
/// four forms (required, nullable, list, nullable list — see the table on
/// each type's required method), which is meant to make adding a fifth rare,
/// but a new field or constraint added to an existing form, or an entirely
/// new scalar type, is still a breaking change for any such implementation.
/// Prefer depending on [Schema] and treat this interface as read-only.
abstract interface class Reader {
  /// Reads a required string field named [name].
  ///
  /// Every scalar type has the same four forms — required, nullable, list,
  /// and nullable list:
  ///
  /// | Type | Required | Nullable | List | Nullable list |
  /// |---|---|---|---|---|
  /// | string | [string] | [stringOrNull] | [stringList] | [stringListOrNull] |
  /// | integer | [integer] | [integerOrNull] | [integerList] | [integerListOrNull] |
  /// | number | [number] | [numberOrNull] | [numberList] | [numberListOrNull] |
  /// | boolean | [boolean] | [booleanOrNull] | [booleanList] | [booleanListOrNull] |
  /// | dateTime | [dateTime] | [dateTimeOrNull] | [dateTimeList] | [dateTimeListOrNull] |
  /// | enum | [enumValue] | [enumValueOrNull] | [enumList] | [enumListOrNull] |
  /// | object | [object] | [objectOrNull] | [objectList] | [objectListOrNull] |
  String string(
    String name, {
    int? minLength,
    int? maxLength,
    Pattern? pattern,
  });

  /// Reads a required integer field named [name].
  int integer(String name, {int? min, int? max});

  /// Reads a required floating-point field named [name].
  double number(String name, {double? min, double? max});

  /// Reads a required boolean field named [name].
  bool boolean(String name);

  /// Reads a required date-time field named [name], as an ISO 8601 string.
  DateTime dateTime(String name, {DateTime? min, DateTime? max});

  /// Reads an optional string field named [name].
  ///
  /// A separate method rather than a `required` flag on [string]: an
  /// argument cannot change a method's static return type from `String` to
  /// `String?`.
  String? stringOrNull(
    String name, {
    int? minLength,
    int? maxLength,
    Pattern? pattern,
  });

  /// Reads an optional integer field named [name].
  int? integerOrNull(String name, {int? min, int? max});

  /// Reads an optional floating-point field named [name].
  double? numberOrNull(String name, {double? min, double? max});

  /// Reads an optional boolean field named [name].
  bool? booleanOrNull(String name);

  /// Reads an optional date-time field named [name].
  DateTime? dateTimeOrNull(String name, {DateTime? min, DateTime? max});

  /// Reads a required field named [name] that must be one of [values].
  ///
  /// The field is matched against each enum constant's `Enum.name`.
  /// [values] is normally an enum's own `.values`, so it comes from the
  /// schema's declaration rather than from the data being read, which is
  /// why a schema may pass it without that counting as branching on a
  /// value.
  T enumValue<T extends Enum>(String name, List<T> values);

  /// Reads an optional field named [name] that must be one of [values].
  T? enumValueOrNull<T extends Enum>(String name, List<T> values);

  /// Reads a required array of strings named [name].
  ///
  /// [pattern], if given, is checked against every element, not the array
  /// as a whole.
  ///
  /// A separate method from [objectList] rather than one generic list
  /// method: a scalar element has no name of its own for an element reader
  /// to ask for, so there is nothing to hand a nested [Reader]. An object
  /// element does have a name for each of its fields, which [objectList]
  /// reads through [itemSchema] instead.
  List<String> stringList(
    String name, {
    int? minItems,
    int? maxItems,
    Pattern? pattern,
  });

  /// Reads an optional array of strings named [name]. `null` when [name] is
  /// absent; an empty or populated list, never `null`, when it is present.
  List<String>? stringListOrNull(
    String name, {
    int? minItems,
    int? maxItems,
    Pattern? pattern,
  });

  /// Reads a required array of integers named [name]. See [stringList] for
  /// why scalar arrays are a separate method from [objectList].
  List<int> integerList(String name, {int? minItems, int? maxItems});

  /// Reads an optional array of integers named [name].
  List<int>? integerListOrNull(String name, {int? minItems, int? maxItems});

  /// Reads a required array of floating-point numbers named [name].
  List<double> numberList(String name, {int? minItems, int? maxItems});

  /// Reads an optional array of floating-point numbers named [name].
  List<double>? numberListOrNull(String name, {int? minItems, int? maxItems});

  /// Reads a required array of booleans named [name].
  List<bool> booleanList(String name, {int? minItems, int? maxItems});

  /// Reads an optional array of booleans named [name].
  List<bool>? booleanListOrNull(String name, {int? minItems, int? maxItems});

  /// Reads a required array of date-times named [name], each an ISO 8601
  /// string. [min]/[max] are checked against every element, not the array.
  List<DateTime> dateTimeList(
    String name, {
    int? minItems,
    int? maxItems,
    DateTime? min,
    DateTime? max,
  });

  /// Reads an optional array of date-times named [name].
  List<DateTime>? dateTimeListOrNull(
    String name, {
    int? minItems,
    int? maxItems,
    DateTime? min,
    DateTime? max,
  });

  /// Reads a required array named [name], each element one of [values].
  /// See [enumValue] for how an element is matched.
  List<T> enumList<T extends Enum>(
    String name,
    List<T> values, {
    int? minItems,
    int? maxItems,
  });

  /// Reads an optional array named [name], each element one of [values].
  List<T>? enumListOrNull<T extends Enum>(
    String name,
    List<T> values, {
    int? minItems,
    int? maxItems,
  });

  /// Reads a required array of objects named [name], each validated against
  /// [itemSchema]. See [stringList] for why object arrays are a separate
  /// method from the scalar list methods.
  List<A> objectList<A>(
    String name,
    Schema<A> itemSchema, {
    int? minItems,
    int? maxItems,
  });

  /// Reads an optional array of objects named [name], each validated
  /// against [itemSchema].
  List<A>? objectListOrNull<A>(
    String name,
    Schema<A> itemSchema, {
    int? minItems,
    int? maxItems,
  });

  /// Reads a required nested object field named [name], validated against
  /// [schema].
  A object<A>(String name, Schema<A> schema);

  /// Reads an optional nested object field named [name], validated against
  /// [schema] when present.
  A? objectOrNull<A>(String name, Schema<A> schema);
}
