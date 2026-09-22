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
abstract interface class Reader {
  /// Reads a required string field named [name].
  String string(String name, {int? minLength, int? maxLength});

  /// Reads a required integer field named [name].
  int integer(String name, {int? min, int? max});

  /// Reads a required floating-point field named [name].
  double number(String name, {double? min, double? max});

  /// Reads a required boolean field named [name].
  bool boolean(String name);

  /// Reads a required date-time field named [name], as an ISO 8601 string.
  DateTime dateTime(String name);

  /// Reads an optional string field named [name].
  ///
  /// A separate method rather than a `required` flag on [string]: an
  /// argument cannot change a method's static return type from `String` to
  /// `String?`.
  String? stringOrNull(String name, {int? minLength, int? maxLength});

  /// Reads an optional integer field named [name].
  int? integerOrNull(String name, {int? min, int? max});

  /// Reads an optional floating-point field named [name].
  double? numberOrNull(String name, {double? min, double? max});

  /// Reads an optional boolean field named [name].
  bool? booleanOrNull(String name);

  /// Reads an optional date-time field named [name].
  DateTime? dateTimeOrNull(String name);

  /// Reads a required field named [name] that must be one of [values].
  ///
  /// The field is matched against each enum constant's [Enum.name]. [values]
  /// is normally an enum's own `.values`, so it comes from the schema's
  /// declaration rather than from the data being read, which is why a
  /// schema may pass it without that counting as branching on a value.
  T enumValue<T extends Enum>(String name, List<T> values);

  /// Reads an optional field named [name] that must be one of [values].
  T? enumValueOrNull<T extends Enum>(String name, List<T> values);

  /// Reads a required array of strings named [name].
  ///
  /// A separate method from [objectList] rather than one generic list
  /// method: a scalar element has no name of its own for an element reader
  /// to ask for, so there is nothing to hand a nested [Reader]. An object
  /// element does have a name for each of its fields, which [objectList]
  /// reads through [itemSchema] instead.
  List<String> stringList(String name, {int? minItems, int? maxItems});

  /// Reads a required array of integers named [name]. See [stringList] for
  /// why scalar arrays are a separate method from [objectList].
  List<int> integerList(String name, {int? minItems, int? maxItems});

  /// Reads a required array of objects named [name], each validated against
  /// [itemSchema]. See [stringList] for why object arrays are a separate
  /// method from the scalar list methods.
  List<A> objectList<A>(
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
