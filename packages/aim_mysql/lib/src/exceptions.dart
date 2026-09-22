/// Thrown when this driver cannot make sense of what the server sent: a
/// packet ends before a value it promised is fully there, or a marker byte
/// does not match any encoding the wire format defines.
///
/// This means "we misread the stream", not "the server refused the
/// request". The server rejecting a command outright -- bad credentials, a
/// syntax error, a missing table -- is a different family of exceptions,
/// added to this file separately once the driver speaks that far.
final class MySqlProtocolException implements Exception {
  MySqlProtocolException(this.message);

  final String message;

  @override
  String toString() => 'MySqlProtocolException: $message';
}
