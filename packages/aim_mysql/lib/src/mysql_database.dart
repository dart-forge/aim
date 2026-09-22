import 'package:aim_database/aim_database.dart';
import 'package:aim_mysql/src/connection.dart';
import 'package:aim_mysql/src/exceptions.dart';
import 'package:aim_mysql/src/sql/placeholders.dart';
import 'package:aim_mysql/src/statement.dart';

/// The `query` / `execute` / `insert` surface [MySqlDatabase] and
/// [MySqlTransaction] both implement.
///
/// Pulled out on its own so the two can share one set of doc comments, and
/// so code that only ever runs statements -- never opens a transaction or
/// touches the pool -- can depend on this instead of either concrete type.
abstract interface class MySqlQueryable {
  /// Runs [sql] and returns the result rows as maps keyed by column name.
  ///
  /// Exactly one of [params] or [args] may be given, not both --
  /// [ArgumentError] otherwise. [params] rewrites `:name` placeholders to
  /// `?` and binds the named values in the order they appear in [sql];
  /// [args] binds `?` placeholders positionally. With neither, [sql] runs
  /// as given, with no parameters bound.
  ///
  /// When two columns share a name, the later one wins -- the same
  /// behaviour `aim_postgres` has, so code written against one tolerates
  /// the other.
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  });

  /// Runs [sql] and returns the number of rows affected.
  ///
  /// See [query] for [params] and [args]. For a statement that reports no
  /// count (DDL, `SET`, ...) this is `0`.
  Future<int> execute(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  });

  /// Runs [sql] -- an `INSERT` -- and returns the `AUTO_INCREMENT` value it
  /// generated, or `0` if the table has none.
  ///
  /// See [query] for [params] and [args].
  ///
  /// This exists because MySQL has no `RETURNING`. The obvious workaround,
  /// a separate `SELECT LAST_INSERT_ID()` through [query], does not work
  /// behind a pool: `LAST_INSERT_ID()` is scoped to the connection that
  /// generated the value, and that `SELECT` can land on a different
  /// connection than the `INSERT` did, silently reporting `0` instead of
  /// the id. Running both statements as one round trip -- which [insert]
  /// does -- is the only way to make the two land on the same connection
  /// without pinning one for the whole call, as a transaction does.
  Future<int> insert(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  });
}

/// A MySQL database backed by a connection pool.
///
/// Every [query], [execute], [insert] and [transaction] checks a
/// connection out of the pool and returns it when done. A connection left
/// unusable by a transport failure is discarded instead of being handed to
/// the next caller.
class MySqlDatabase extends Database implements MySqlQueryable {
  MySqlDatabase._(this._pool);

  final Pool<MySqlConnection> _pool;

  /// Connects to a MySQL database and opens a connection pool.
  ///
  /// The [connectionString] should be in the format:
  /// `mysql://username:password@host:port/database?sslmode=mode&sslrootcert=/path/to/ca.crt`
  ///
  /// Supported SSL modes: disable, prefer, require, verify-ca, verify-full
  ///
  /// One connection is opened immediately so that a bad connection string
  /// or failed authentication surfaces here. Further connections are
  /// opened on demand up to [maxConnections].
  ///
  /// - [acquireTimeout]: how long a call waits for a free connection before
  ///   throwing [PoolTimeoutException].
  /// - [idleTimeout]: idle connections unused for this long are closed.
  ///   [Duration.zero] disables.
  /// - [maxLifetime]: connections older than this are closed once idle.
  ///   [Duration.zero] disables.
  /// - [validationInterval]: idle connections unused for at least this long
  ///   are pinged before reuse. [Duration.zero] pings on every use.
  ///
  /// Example:
  /// ```dart
  /// final db = await MySqlDatabase.connect(
  ///   'mysql://user:pass@localhost:3306/mydb?sslmode=require',
  ///   maxConnections: 20,
  /// );
  /// ```
  static Future<MySqlDatabase> connect(
    String connectionString, {
    int maxConnections = 10,
    Duration acquireTimeout = const Duration(seconds: 30),
    Duration idleTimeout = const Duration(minutes: 10),
    Duration maxLifetime = const Duration(minutes: 30),
    Duration validationInterval = const Duration(seconds: 30),
  }) async {
    final settings = MySqlConnectionSettings.parse(connectionString);
    final pool = Pool<MySqlConnection>(
      create: () => MySqlConnection.connect(settings),
      validate: (conn) => conn.ping(),
      destroy: (conn) => conn.close(),
      options: PoolOptions(
        maxConnections: maxConnections,
        acquireTimeout: acquireTimeout,
        idleTimeout: idleTimeout,
        maxLifetime: maxLifetime,
        validationInterval: validationInterval,
      ),
    );
    try {
      final first = await pool.acquire();
      await pool.release(first);
    } catch (_) {
      await pool.close();
      rethrow;
    }
    return MySqlDatabase._(pool);
  }

  /// Snapshot of the connection pool.
  PoolStats get poolStats => _pool.stats;

  @override
  Future<void> close() => _pool.close();

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  }) {
    return _withConnection((conn, _) async {
      final results = await _runQueryable(
        conn,
        sql,
        params: params,
        args: args,
      );
      return _resultsToMaps(results);
    });
  }

  @override
  Future<int> execute(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  }) {
    return _withConnection((conn, _) async {
      final results = await _runQueryable(
        conn,
        sql,
        params: params,
        args: args,
      );
      return results.totalAffectedRows;
    });
  }

  @override
  Future<int> insert(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  }) {
    return _withConnection((conn, _) async {
      final results = await _runQueryable(
        conn,
        sql,
        params: params,
        args: args,
      );
      return results.lastInsertId;
    });
  }

  /// Runs [fn] inside `START TRANSACTION` / `COMMIT`, rolling back if [fn]
  /// throws. The connection [fn] is handed, through [MySqlTransaction], is
  /// pinned for the whole call, so every statement [fn] runs lands on the
  /// same connection -- which is what lets the body see its own
  /// uncommitted writes and what keeps them invisible to everyone else
  /// until it commits.
  ///
  /// MySQL commits a transaction implicitly when it runs DDL such as
  /// `CREATE TABLE`. [MySqlTransaction] notices this on the statement that
  /// caused it and raises [MySqlTransactionEndedByDdl] instead of letting
  /// [fn] carry on believing the rest of its work is still inside a
  /// transaction that a later failure could undo. When that happens, the
  /// `ROLLBACK` below still runs, but there is nothing left open for it to
  /// roll back -- the statements before the DDL are already committed and
  /// permanent.
  ///
  /// A `ROLLBACK` sent to a connection with no open transaction is not an
  /// error either way: MySQL just answers OK. That is also what happens
  /// when the server itself already rolled the transaction back, as it
  /// does for whichever side of a deadlock it picks as the victim.
  @override
  Future<T> transaction<T>(Future<T> Function(MySqlTransaction tx) fn) {
    return _withConnection((conn, discard) async {
      await conn.runTextQuery('START TRANSACTION');
      try {
        final result = await fn(MySqlTransaction._(conn));
        await conn.runTextQuery('COMMIT');
        return result;
      } catch (_) {
        if (conn.isOpen) {
          try {
            await conn.runTextQuery('ROLLBACK');
          } catch (_) {
            // The caller needs the original error, not this one. A
            // connection whose ROLLBACK failed may still be inside an
            // aborted transaction, so never hand it back to the pool.
            discard();
          }
        }
        rethrow;
      }
    });
  }

  Future<T> _withConnection<T>(
    Future<T> Function(MySqlConnection conn, void Function() discard) fn,
  ) async {
    if (_pool.isClosed) throw StateError(mysqlClosedMessage);
    final conn = await _pool.acquire();
    var forceDiscard = false;
    try {
      return await fn(conn, () => forceDiscard = true);
    } finally {
      // A connection released while a transaction was left open on it --
      // which cannot happen through this class's own transaction(), but
      // could through a caller running START TRANSACTION by hand via
      // execute() -- would poison the next borrower, so isOpen is checked
      // rather than assumed.
      await _pool.release(conn, discard: forceDiscard || !conn.isOpen);
    }
  }
}

/// A transaction pinned to a single pooled connection for its whole
/// lifetime. Obtained via [MySqlDatabase.transaction].
class MySqlTransaction implements Transaction, MySqlQueryable {
  MySqlTransaction._(this._connection);

  final MySqlConnection _connection;

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  }) async {
    return _resultsToMaps(await _runChecked(sql, params: params, args: args));
  }

  @override
  Future<int> execute(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  }) async {
    return (await _runChecked(
      sql,
      params: params,
      args: args,
    )).totalAffectedRows;
  }

  @override
  Future<int> insert(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  }) async {
    return (await _runChecked(sql, params: params, args: args)).lastInsertId;
  }

  /// Runs [sql] as [MySqlQueryable] promises, then checks that this
  /// transaction is still open.
  ///
  /// MySQL commits implicitly on DDL, so the statement that just ran may
  /// have ended the transaction without saying so anywhere but its own
  /// reply: `SERVER_STATUS_IN_TRANS` is set on every reply for as long as
  /// an explicit transaction stays open, so a reply that no longer has it
  /// set means this statement is the one that ended it. [sql] is
  /// checked -- and, if it did, [MySqlTransactionEndedByDdl] is raised
  /// naming it -- immediately, in this same call, rather than on some
  /// later statement: the caller must not be allowed to run another
  /// statement believing it is still inside a transaction that a failure
  /// could still roll back.
  Future<MySqlResultSets> _runChecked(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  }) async {
    final results = await _runQueryable(
      _connection,
      sql,
      params: params,
      args: args,
    );
    if (!results.inTransaction) {
      throw MySqlTransactionEndedByDdl(sql);
    }
    return results;
  }
}

/// Thrown from inside a [MySqlTransaction] body when a statement implicitly
/// committed the transaction -- which is what MySQL does for DDL, such as
/// `CREATE TABLE`, run inside one.
///
/// By the time this is thrown, [sql] has already run, and its effect --
/// along with everything the transaction did before it -- is committed and
/// permanent. The `ROLLBACK` that [MySqlDatabase.transaction] sends once
/// this propagates out of the body has nothing left to undo.
final class MySqlTransactionEndedByDdl implements Exception {
  MySqlTransactionEndedByDdl(this.sql);

  /// The statement whose own reply showed the transaction had ended.
  final String sql;

  @override
  String toString() =>
      'MySqlTransactionEndedByDdl: running this statement implicitly '
      'committed the transaction. Everything before it is already '
      'committed and cannot be rolled back.\nSQL: $sql';
}

/// Runs [sql] on [connection] for [MySqlDatabase] and [MySqlTransaction]
/// alike: converts named parameters to `?` when [params] is given, decides
/// whether [sql] can go through a prepared statement or has to run as a
/// plain `COM_QUERY`, and refreshes [MySqlConnection.dialect] when [sql]
/// just changed `sql_mode` out from under it.
///
/// Exactly one of [params] or [args] may be given -- [ArgumentError]
/// otherwise, since silently preferring one would bind the wrong values.
Future<MySqlResultSets> _runQueryable(
  MySqlConnection connection,
  String sql, {
  Map<String, dynamic>? params,
  List<dynamic>? args,
}) async {
  final hasParams = params != null && params.isNotEmpty;
  final hasArgs = args != null && args.isNotEmpty;

  if (hasParams && hasArgs) {
    throw ArgumentError(
      'Cannot specify both named parameters (params) and positional '
      'parameters (args)',
    );
  }

  String runSql;
  List<Object?> values;
  if (hasParams) {
    (runSql, values) = rewriteNamedParameters(
      sql,
      params,
      dialect: connection.dialect,
    );
  } else {
    runSql = sql;
    values = args ?? const [];
  }

  // SET cannot be prepared -- see MySqlConnection.runTextQuery's doc
  // comment -- so it has to run as plain text instead. Every other
  // statement this driver is asked to run always can be, which is what
  // lets it be cached across repeated calls and decoded with real Dart
  // types rather than the strings runTextQuery hands back.
  final results = values.isEmpty && _isSetStatement(runSql)
      ? await connection.runTextQuery(runSql)
      : await executeStatement(
          connection,
          await connection.statements.get(runSql),
          values,
        );

  // MySqlConnection.dialect is read from sql_mode once, at connect time,
  // and cached from then on -- reading it fresh before every statement
  // would spend a round trip nothing else needs. A SET that just changed
  // sql_mode would leave that cache stale, and the very next statement's
  // placeholders would be scanned under the wrong rule -- silently, since
  // a literal ending in the wrong place is not a protocol error.
  if (_setsSqlMode(runSql)) {
    await connection.refreshSqlMode();
  }

  return results;
}

/// Whether [sql] is, or starts as, a `SET` statement -- case- and
/// leading-whitespace-insensitively.
bool _isSetStatement(String sql) => sql.trim().toUpperCase().startsWith('SET');

/// Whether [sql] is a `SET` that touches `sql_mode`.
///
/// Requiring [_isSetStatement] first, rather than searching the whole
/// string for `SQL_MODE`, is deliberate: a `SELECT ... LIKE '%sql_mode%'`
/// cannot possibly have changed the session's `sql_mode`, and without this
/// restriction it would still cost an extra round trip re-reading a value
/// that never moved.
bool _setsSqlMode(String sql) =>
    _isSetStatement(sql) && sql.toUpperCase().contains('SQL_MODE');

/// Converts [results]' one row-bearing result set, if it has one, to the
/// list of maps keyed by column name that [MySqlQueryable.query] promises.
///
/// `null` -- no result set had rows, e.g. a `SET` -- becomes the empty
/// list, the same list a `SELECT` matching no rows would produce; the two
/// are indistinguishable to a caller of [MySqlQueryable.query] and must
/// stay that way.
List<Map<String, dynamic>> _resultsToMaps(MySqlResultSets results) {
  final withRows = results.withRows;
  if (withRows == null) return const [];
  final columns = withRows.columns;
  return [
    for (final row in withRows.rows)
      <String, dynamic>{
        // Later columns overwrite earlier ones of the same name -- see
        // MySqlQueryable.query's doc comment.
        for (var i = 0; i < columns.length; i++) columns[i].name: row[i],
      },
  ];
}
