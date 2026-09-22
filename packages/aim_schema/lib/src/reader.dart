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

  /// Reads an optional string field named [name].
  ///
  /// A separate method rather than a `required` flag on [string]: an
  /// argument cannot change a method's static return type from `String` to
  /// `String?`.
  String? stringOrNull(String name, {int? minLength, int? maxLength});
}
