import 'package:aim_mysql/src/protocol/packets.dart';

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

/// The one wording for a call that arrives on a database that is already
/// closed.
///
/// Which check fails a given call depends only on how far it had got
/// before close came, and a caller can act on neither difference, so it
/// must not hear two different wordings for it. What actually gets
/// thrown is a plain `StateError` built from this constant --
/// `throw StateError(mysqlClosedMessage)` -- the same shape `aim_sqlite`
/// uses for the same purpose, rather than a dedicated exception type.
const mysqlClosedMessage = 'MySqlDatabase is closed';

/// The server refused a request: a constraint violation, a permissions
/// problem, a syntax error, or anything else it reports with an ERR
/// packet.
///
/// Carries [errorCode], [sqlState] and [message] from that packet, plus
/// [sql] when the statement that caused it is known. Every subtype below
/// -- one per errno this driver gives a name to -- `extends` this rather
/// than merely implementing it, so `isA<MySqlException>()` catches all of
/// them: a caller that only wants to know whether the database refused
/// the request can catch this one type instead of listing every subtype
/// there is or ever will be.
class MySqlException implements Exception {
  MySqlException({
    required this.errorCode,
    required this.sqlState,
    required this.message,
    this.sql,
  });

  /// The server's numeric error code, e.g. `1062` for a duplicate key.
  /// [mysqlErrorFor] classifies on this, not [sqlState]: SQLSTATE `23000`
  /// covers a unique violation, a NOT NULL violation and a foreign-key
  /// violation alike, which is exactly the distinction a caller wants
  /// drawn.
  final int errorCode;

  /// The five-character SQLSTATE the server sent alongside [errorCode].
  /// Carried through in full, but not what classification is based on --
  /// see [errorCode].
  final String sqlState;

  /// The server's own message text. English prose, and free to change
  /// between server versions; branch on [errorCode], not this.
  final String message;

  /// The statement that was running when the server sent this, if one
  /// was.
  final String? sql;

  @override
  String toString() {
    final head = '$runtimeType($errorCode): $message';
    return sql == null ? head : '$head\nSQL: $sql';
  }
}

/// errno 1062: a UNIQUE or PRIMARY KEY constraint rejected a row that
/// duplicates one already there.
final class MySqlUniqueViolation extends MySqlException {
  MySqlUniqueViolation({
    required super.errorCode,
    required super.sqlState,
    required super.message,
    super.sql,
  });
}

/// errno 1048: a NOT NULL column was given no value, or an explicit NULL.
final class MySqlNotNullViolation extends MySqlException {
  MySqlNotNullViolation({
    required super.errorCode,
    required super.sqlState,
    required super.message,
    super.sql,
  });
}

/// errno 1216, 1217, 1451 or 1452: a row could not be written because it
/// would break a foreign key relationship. MySQL reports the child-row
/// side and the parent-row side under different numbers, and reports each
/// of those two again under a second, InnoDB-specific number that adds
/// detail to the message -- four numbers, but one thing for a caller to
/// do about any of them: the statement named a row on the other side of
/// the relationship that does not agree with this one.
final class MySqlForeignKeyViolation extends MySqlException {
  MySqlForeignKeyViolation({
    required super.errorCode,
    required super.sqlState,
    required super.message,
    super.sql,
  });
}

/// errno 3819: a CHECK constraint rejected the row.
final class MySqlCheckViolation extends MySqlException {
  MySqlCheckViolation({
    required super.errorCode,
    required super.sqlState,
    required super.message,
    super.sql,
  });
}

/// errno 1213: this transaction was picked as the victim to break a
/// deadlock. Safe to retry right away -- it was rolled back in full, and
/// whatever it was waiting on may already be free.
final class MySqlDeadlock extends MySqlException {
  MySqlDeadlock({
    required super.errorCode,
    required super.sqlState,
    required super.message,
    super.sql,
  });
}

/// errno 1205: a statement waited longer than `innodb_lock_wait_timeout`
/// for a lock and gave up. Unlike [MySqlDeadlock], nothing here says the
/// lock is free now -- retrying immediately typically just waits again.
final class MySqlLockWaitTimeout extends MySqlException {
  MySqlLockWaitTimeout({
    required super.errorCode,
    required super.sqlState,
    required super.message,
    super.sql,
  });
}

/// errno 1044, 1045 or 1698: the server would not authenticate this user,
/// or this user has no rights over the database named. The three numbers
/// are slightly different checks -- no grant on the named database, a
/// wrong password, a plugin that refuses without one -- but a caller's
/// response to all three is the same: the credentials or grants are
/// wrong, not the statement.
final class MySqlAccessDenied extends MySqlException {
  MySqlAccessDenied({
    required super.errorCode,
    required super.sqlState,
    required super.message,
    super.sql,
  });
}

/// Classifies [err] by its errno into one of the [MySqlException]
/// subtypes above, or into a plain [MySqlException] when no subtype
/// matches. [sql] rides along either way as context; it plays no part in
/// the classification itself.
///
/// An errno with no dedicated subtype is not swallowed or blurred into
/// something vaguer: it still comes back as a [MySqlException] carrying
/// its own [MySqlException.errorCode], so a caller can branch on the raw
/// code even without a type for it.
MySqlException mysqlErrorFor(ErrPacket err, {String? sql}) {
  final errorCode = err.errorCode;
  final sqlState = err.sqlState;
  final message = err.message;

  switch (errorCode) {
    case 1062:
      return MySqlUniqueViolation(
        errorCode: errorCode,
        sqlState: sqlState,
        message: message,
        sql: sql,
      );
    case 1048:
      return MySqlNotNullViolation(
        errorCode: errorCode,
        sqlState: sqlState,
        message: message,
        sql: sql,
      );
    case 1216:
    case 1217:
    case 1451:
    case 1452:
      return MySqlForeignKeyViolation(
        errorCode: errorCode,
        sqlState: sqlState,
        message: message,
        sql: sql,
      );
    case 3819:
      return MySqlCheckViolation(
        errorCode: errorCode,
        sqlState: sqlState,
        message: message,
        sql: sql,
      );
    case 1213:
      return MySqlDeadlock(
        errorCode: errorCode,
        sqlState: sqlState,
        message: message,
        sql: sql,
      );
    case 1205:
      return MySqlLockWaitTimeout(
        errorCode: errorCode,
        sqlState: sqlState,
        message: message,
        sql: sql,
      );
    case 1044:
    case 1045:
    case 1698:
      return MySqlAccessDenied(
        errorCode: errorCode,
        sqlState: sqlState,
        message: message,
        sql: sql,
      );
    default:
      return MySqlException(
        errorCode: errorCode,
        sqlState: sqlState,
        message: message,
        sql: sql,
      );
  }
}

/// A column's raw bytes were read correctly off the wire but could not be
/// turned into the Dart type asked for.
///
/// Kept apart from [MySqlException]: nothing here was refused by the
/// server, so classifying it alongside a unique violation or a deadlock
/// would tell a caller catching [MySqlException] that the database said
/// no, when what actually happened is that this driver could not make
/// sense of a value it was itself sent successfully. Kept apart from
/// [MySqlProtocolException] too, for the same reason that one is kept
/// apart from [MySqlException]: that type means the byte stream itself
/// made no sense -- a packet cut short, a marker byte nothing defines --
/// while this one means the stream was read fine and the value at the end
/// of it simply did not fit the type asked for.
final class MySqlDecodeException implements Exception {
  MySqlDecodeException(this.message);

  final String message;

  @override
  String toString() => 'MySqlDecodeException: $message';
}
