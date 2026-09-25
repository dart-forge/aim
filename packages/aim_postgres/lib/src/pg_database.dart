import 'package:aim_database/aim_database.dart';
import 'package:aim_postgres/src/pg_connection.dart';
import 'package:aim_postgres/src/named_parameters.dart';

abstract interface class PostgresQueryable {
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  });

  Future<int> execute(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  });
}

/// PostgreSQL database implementation backed by a connection pool.
///
/// Every [query], [execute] and [transaction] checks a connection out of
/// the pool and returns it when done. Connections that suffered a
/// transport failure are discarded and replaced transparently.
class PostgresDatabase extends Database implements PostgresQueryable {
  PostgresDatabase._(this._pool);

  final Pool<PostgresConnection> _pool;

  /// Connects to a PostgreSQL database and opens a connection pool.
  ///
  /// The [connectionString] should be in the format:
  /// `postgresql://username:password@host:port/database?sslmode=mode&sslrootcert=/path/to/ca.crt`
  ///
  /// Supported SSL modes: disable, allow, prefer, require, verify-ca, verify-full
  ///
  /// One connection is opened immediately so that a bad connection string or
  /// failed authentication surfaces here. Further connections are opened on
  /// demand up to [maxConnections].
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
  /// final db = await PostgresDatabase.connect(
  ///   'postgresql://user:pass@localhost:5432/mydb?sslmode=require',
  ///   maxConnections: 20,
  /// );
  /// ```
  static Future<PostgresDatabase> connect(
    String connectionString, {
    int maxConnections = 10,
    Duration acquireTimeout = const Duration(seconds: 30),
    Duration idleTimeout = const Duration(minutes: 10),
    Duration maxLifetime = const Duration(minutes: 30),
    Duration validationInterval = const Duration(seconds: 30),
  }) async {
    final pool = Pool<PostgresConnection>(
      create: () => PostgresConnection.connect(connectionString),
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
    return PostgresDatabase._(pool);
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
      final result = await _runQuery(conn, sql, params: params, args: args);
      return result.toMaps();
    });
  }

  @override
  Future<int> execute(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  }) {
    return _withConnection((conn, _) async {
      final result = await _runQuery(conn, sql, params: params, args: args);
      return result.affectedRows;
    });
  }

  @override
  Future<T> transaction<T>(Future<T> Function(PostgresTransaction tx) fn) {
    return _withConnection((conn, discard) async {
      await conn.sendSimpleQuery('BEGIN');
      try {
        final result = await fn(PostgresTransaction(conn));
        await conn.sendSimpleQuery('COMMIT');
        return result;
      } catch (_) {
        if (!conn.isBroken) {
          try {
            await conn.sendSimpleQuery('ROLLBACK');
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
    Future<T> Function(PostgresConnection conn, void Function() discard) fn,
  ) async {
    if (_pool.isClosed) throw StateError('PostgresDatabase is closed');
    final conn = await _pool.acquire();
    var forceDiscard = false;
    try {
      return await fn(conn, () => forceDiscard = true);
    } finally {
      // A connection handed back while still inside a transaction (manual
      // BEGIN through execute(), or a stashed PostgresTransaction) would
      // poison the next borrower, so it is discarded instead of reused.
      await _pool.release(
        conn,
        discard: forceDiscard || conn.isBroken || conn.inTransaction,
      );
    }
  }
}

/// A transaction pinned to a single pooled connection for its whole
/// lifetime. Obtained via [PostgresDatabase.transaction].
class PostgresTransaction implements Transaction, PostgresQueryable {
  PostgresTransaction(this._connection);

  final PostgresConnection _connection;

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  }) async {
    final result = await _runQuery(
      _connection,
      sql,
      params: params,
      args: args,
    );
    return result.toMaps();
  }

  @override
  Future<int> execute(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  }) async {
    final result = await _runQuery(
      _connection,
      sql,
      params: params,
      args: args,
    );
    return result.affectedRows;
  }
}

/// Shared query dispatch: picks Simple vs Extended Query Protocol and
/// converts named parameters. Used by both [PostgresDatabase] and
/// [PostgresTransaction].
Future<QueryResult> _runQuery(
  PostgresConnection conn,
  String sql, {
  Map<String, dynamic>? params,
  List<dynamic>? args,
}) {
  final hasParams = params != null && params.isNotEmpty;
  final hasArgs = args != null && args.isNotEmpty;

  if (hasParams && hasArgs) {
    throw ArgumentError(
      'Cannot specify both named parameters (params) and positional parameters (args)',
    );
  }

  if (hasParams) {
    final (convertedSql, positionalParams) = convertNamedParameters(
      sql,
      params,
    );
    return conn.sendExtendedQuery(convertedSql, positionalParams);
  }

  if (hasArgs) {
    return conn.sendExtendedQuery(sql, args);
  }

  return conn.sendSimpleQuery(sql);
}
