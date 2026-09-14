/// A database connection (or pool) that runs SQL.
///
/// ## Value contract
///
/// Drivers return column values already converted to Dart types; callers do
/// not parse strings. The mapping is driver-specific, but every driver
/// guarantees:
///
/// - integers → `int`, floating point → `double`, booleans → `bool`
/// - arbitrary-precision decimals (`numeric` / `decimal`) → `String`
/// - dates and timestamps → `DateTime` with `isUtc == true`; a timestamp
///   stored without a time zone is read as a UTC wall clock
/// - JSON → the result of `jsonDecode`
/// - binary → `Uint8List`
/// - types the driver does not know → `String`
///
/// Values accepted as parameters mirror the values returned, so a value read
/// from one query can be passed to the next.
abstract class Database {
  /// Runs [sql] and returns the result rows as maps keyed by column name.
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  });

  /// Runs [sql] and returns the number of rows affected.
  ///
  /// For `INSERT` / `UPDATE` / `DELETE` this is the reported row count. For
  /// statements that report no count (DDL, `SET`, ...) it is 0. When a single
  /// call runs several statements the counts are summed.
  Future<int> execute(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  });

  /// Runs [fn] inside a transaction, committing on success and rolling back
  /// when [fn] throws.
  Future<T> transaction<T>(Future<T> Function(Transaction tx) fn);

  /// Releases the underlying connection(s).
  Future<void> close();
}

/// Queries bound to one open transaction. Values follow the same contract
/// as [Database].
abstract class Transaction {
  /// See [Database.query].
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  });

  /// See [Database.execute].
  Future<int> execute(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  });
}
