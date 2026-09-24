import 'package:aim_schema/src/output.dart';

/// A response value made only by calling a [ResponseEntry], so a typed
/// handler can only return one from its own [Responses].
///
/// Opaque to users: there is nothing to build one from except an entry.
final class Reply {
  Reply._(this.status, this.body);

  /// The HTTP status code declared for the [ResponseEntry] that made this.
  final int status;

  /// This reply's body, already encoded to JSON-ready values.
  final Map<String, Object?> body;
}

/// One response a route can return: a status code, the [Output] its body
/// must match, and an optional human-readable description.
///
/// Calling an entry with a value encodes it eagerly through [output] and
/// wraps the result in a [Reply] — the only way to make one.
final class ResponseEntry<T> {
  ResponseEntry._(this.status, this.output, this.description);

  /// The HTTP status code this entry declares.
  final int status;

  /// What a value passed to this entry must match.
  final Output<T> output;

  /// A human-readable description of this response, if one was given.
  final String? description;

  /// Encodes [value] through [output] and wraps it in a [Reply].
  ///
  /// Throws [ResponseValidationException] if [value] does not match
  /// [output].
  Reply call(T value) => Reply._(status, output.encode(value));
}

/// Builds [ResponseEntry]s for one [responses] call.
///
/// Only valid while the [responses] closure that received it is still
/// running — calling it afterward throws [StateError].
final class ResponseBuilder {
  ResponseBuilder._();

  bool _closed = false;
  final Set<int> _statuses = {};
  final List<ResponseEntry<Object?>> _entries = [];

  /// Declares one response: [status] must be a valid HTTP status
  /// (100-599) not already used in this [responses] call.
  ResponseEntry<T> call<T>(
    int status,
    Output<T> output, {
    String? description,
  }) {
    if (_closed) {
      throw StateError(
        'This ResponseBuilder can no longer be used; it is only valid '
        'while the responses() closure that received it is running.',
      );
    }
    if (status < 100 || status > 599) {
      throw ArgumentError.value(
        status,
        'status',
        'must be between 100 and 599',
      );
    }
    if (!_statuses.add(status)) {
      throw ArgumentError.value(status, 'status', 'already declared');
    }
    final entry = ResponseEntry<T>._(status, output, description);
    _entries.add(entry);
    return entry;
  }
}

/// The result of a [responses] call: the record [build] returned, plus
/// every entry it declared in the order they were declared.
final class Responses<R> {
  Responses._(this.entries, this.all);

  /// The record [build] returned, keeping each entry's type.
  final R entries;

  /// Every [ResponseEntry] declared in this call, in declaration order.
  final List<ResponseEntry<Object?>> all;
}

/// Declares the responses a route can return.
///
/// [build] runs once, eagerly, and receives a [ResponseBuilder] to declare
/// each response with. The record it returns is available afterward as
/// [Responses.entries], typed exactly as [build] built it:
///
/// ```dart
/// final userResponses = responses((r) => (
///       ok: r(200, userOut),
///       notFound: r(404, errorOut, description: 'no such user'),
///     ));
///
/// final reply = userResponses.entries.ok(user);
/// ```
Responses<R> responses<R>(R Function(ResponseBuilder r) build) {
  final builder = ResponseBuilder._();
  final entries = build(builder);
  builder._closed = true;
  return Responses._(entries, List.unmodifiable(builder._entries));
}
