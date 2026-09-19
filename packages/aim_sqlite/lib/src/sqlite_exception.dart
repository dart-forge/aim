/// The one wording for a statement that arrives on a closed database.
///
/// Which check fails a given call depends only on how far it had got when
/// close came: SqliteDatabase refuses what has not been sent yet, and the
/// reader pool fails a read it had already queued. A caller can act on
/// neither difference, so it must not hear two different things -- and there
/// were five wordings of this before, all reachable, all decided by timing.
///
/// The worker handle's "the SQLite worker isolate is stopped" is not one of
/// them: an isolate that has stopped without the database being closed is a
/// different condition and says so.
const sqliteClosedMessage = 'SqliteDatabase is closed';

/// A statement failed inside SQLite.
class SqliteException implements Exception {
  SqliteException({
    required this.extendedResultCode,
    required this.message,
    required this.sql,
  });

  /// The full code, e.g. 2067 for SQLITE_CONSTRAINT_UNIQUE. Carried so
  /// callers can branch on the exact failure instead of matching on
  /// [message], which is English prose and free to change.
  final int extendedResultCode;

  /// The low 8 bits, e.g. 19 for SQLITE_CONSTRAINT.
  int get resultCode => extendedResultCode & 0xff;

  /// sqlite3_errmsg.
  final String message;

  /// The statement that failed.
  final String sql;

  @override
  String toString() =>
      'SqliteException($extendedResultCode): $message\nSQL: $sql';
}

/// A column value could not be turned into the Dart type its declared type
/// promises.
class SqliteDecodeException implements Exception {
  SqliteDecodeException({
    required this.column,
    required this.declType,
    required this.rawValue,
    required this.message,
  });

  final String column;

  /// The normalised declared type, or null when the column had none.
  final String? declType;

  /// The value as SQLite stored it.
  final Object? rawValue;

  final String message;

  @override
  String toString() =>
      'SqliteDecodeException: $message (column "$column", declared '
      '${declType ?? "nothing"}, stored $rawValue)';
}

/// A statement gave up waiting for a connection to run on.
///
/// The read-only connections take one statement at a time, so a read that
/// arrives while they are all busy waits for one to come free -- and is
/// failed with this once it has waited the `acquireTimeout` it was opened
/// with, rather than queueing without end behind however much work is
/// already in front of it.
///
/// Nothing ran. The statement never reached a connection, so there is no
/// half-applied batch behind this and running it again repeats nothing.
class SqliteTimeoutException implements Exception {
  SqliteTimeoutException({required this.timeout, required this.sql});

  /// How long it waited: the `acquireTimeout` the database was opened with.
  final Duration timeout;

  /// The statement that never got a connection.
  final String sql;

  @override
  String toString() =>
      'SqliteTimeoutException: no SQLite connection came free within '
      '${timeout.inMilliseconds}ms\nSQL: $sql';
}

/// No libsqlite3 could be loaded.
///
/// This driver does not bundle libsqlite3, so this is what a machine without
/// one -- or a `libraryPath` pointing at nothing -- gets from
/// `SqliteDatabase.open`, rethrown out of the worker isolate that tried to
/// load it. [searched] is every path that was tried, in the order they were
/// tried, so the failure says where a library could go and not only that
/// there is none.
///
/// A library that did load and was turned down for its version is a
/// different failure, [SqliteLibraryTooOldException], and catching this one
/// does not catch that one.
class SqliteLibraryNotFoundException implements Exception {
  SqliteLibraryNotFoundException(this.searched, this.cause);

  /// Every path that was tried, in order.
  final List<String> searched;

  /// The failure from the last attempt.
  final Object cause;

  @override
  String toString() =>
      'SqliteLibraryNotFoundException: could not load libsqlite3. '
      'Looked in: ${searched.join(", ")}. Last error: $cause';
}

/// A libsqlite3 was loaded and is older than this driver can run on.
///
/// Kept apart from [SqliteLibraryNotFoundException] because the two call for
/// different things: there is a library here, at [path], and it is its
/// version that is wrong. Both versions are in the form
/// sqlite3_libversion_number reports -- 3008007 for 3.8.7.
class SqliteLibraryTooOldException implements Exception {
  SqliteLibraryTooOldException({
    required this.path,
    required this.version,
    required this.requiredVersion,
  });

  /// The library that loaded and was turned down.
  final String path;

  /// What it reported, e.g. 3007017 for 3.7.17.
  final int version;

  /// The lowest version this driver runs on, in the same form.
  final int requiredVersion;

  @override
  String toString() =>
      'SqliteLibraryTooOldException: libsqlite3 at "$path" is version '
      '$version, older than the $requiredVersion this driver needs. That '
      'floor comes from sqlite3_malloc64, the newest function it calls.';
}
