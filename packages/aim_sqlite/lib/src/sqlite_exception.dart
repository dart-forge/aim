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
