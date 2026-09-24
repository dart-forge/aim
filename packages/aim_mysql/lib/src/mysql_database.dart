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
  /// the id. [insert] never runs a second statement at all: the id is
  /// already sitting in the `INSERT`'s own OK packet, so reading it back
  /// costs nothing beyond running the `INSERT` itself, on whichever
  /// connection the pool happens to hand out.
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
    return _withConnection((conn, discard) async {
      final results = await _runQueryable(
        conn,
        sql,
        params: params,
        args: args,
      );
      if (_leavesConnectionUnsafeForPool(sql, results)) discard();
      return (_resultsToMaps(results), results.inTransaction);
    });
  }

  @override
  Future<int> execute(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  }) {
    return _withConnection((conn, discard) async {
      final results = await _runQueryable(
        conn,
        sql,
        params: params,
        args: args,
      );
      if (_leavesConnectionUnsafeForPool(sql, results)) discard();
      return (results.totalAffectedRows, results.inTransaction);
    });
  }

  @override
  Future<int> insert(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  }) {
    return _withConnection((conn, discard) async {
      final results = await _runQueryable(
        conn,
        sql,
        params: params,
        args: args,
      );
      if (_leavesConnectionUnsafeForPool(sql, results)) discard();
      return (results.lastInsertId, results.inTransaction);
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
  /// `CREATE TABLE` -- whether or not that statement itself goes on to
  /// succeed. [MySqlTransaction] notices this on the statement that caused
  /// it, success or failure alike, and raises [MySqlTransactionEndedByDdl]
  /// instead of letting [fn] carry on believing the rest of its work is
  /// still inside a transaction that a later failure could undo. When that
  /// happens, the `ROLLBACK` below still runs, but there is nothing left
  /// open for it to roll back. If the statement that ended it succeeded,
  /// the statements before it are committed and permanent; if it failed,
  /// whether they are committed or rolled back is not something this
  /// driver can tell -- see [MySqlTransactionEndedByDdl]'s own doc comment.
  ///
  /// A `ROLLBACK` sent to a connection with no open transaction is not an
  /// error either way: MySQL just answers OK. That is also what happens
  /// when the server itself already rolled the transaction back, as it
  /// does for whichever side of a deadlock it picks as the victim.
  @override
  Future<T> transaction<T>(Future<T> Function(MySqlTransaction tx) fn) {
    return _withConnection((conn, discard) async {
      await conn.runTextQuery('START TRANSACTION');
      final tx = MySqlTransaction._(conn, discard);
      try {
        final result = await fn(tx);
        // Set before the COMMIT, not after: a caller holding tx past this
        // point must see it as ended even if COMMIT itself is still the
        // very next thing to happen on the connection.
        tx._done = true;
        await conn.runTextQuery('COMMIT');
        // Already committed, so there is nothing left open for
        // _withConnection's own inTransaction check to act on below.
        return (result, false);
      } catch (_) {
        tx._done = true;
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
    Future<(T, bool)> Function(MySqlConnection conn, void Function() discard)
    fn,
  ) async {
    if (_pool.isClosed) throw StateError(mysqlClosedMessage);
    final conn = await _pool.acquire();
    var forceDiscard = false;
    var leftTransactionOpen = false;
    try {
      final (result, inTransaction) = await fn(conn, () => forceDiscard = true);
      leftTransactionOpen = inTransaction;
      return result;
    } finally {
      // isOpen catches a connection a transport failure already made
      // unusable. leftTransactionOpen catches the other way a caller's own
      // SQL can leave a connection unfit to recycle while still reporting
      // isOpen: an explicit transaction left open by something other than
      // this method's own START TRANSACTION / COMMIT / ROLLBACK. Handing a
      // connection like that back to the pool would poison whichever
      // unrelated caller borrows it next: a COMMIT or ROLLBACK it never
      // asked for would land on this caller's still-open work instead of
      // its own.
      //
      // A `SET autocommit = 0` is not caught by this check: its own OK
      // reply has `SERVER_STATUS_IN_TRANS` cleared, because autocommit
      // going off does not by itself open a transaction -- the next
      // statement that runs on the connection is what does that, and by
      // then the connection may already be back in the pool, in some
      // other caller's hands. `_leavesConnectionUnsafeForPool`, called at
      // every call site above and from `MySqlTransaction._runChecked`, is
      // what catches that case instead, by discarding on the SET itself
      // rather than waiting for a symptom of it.
      await _pool.release(
        conn,
        discard: forceDiscard || !conn.isOpen || leftTransactionOpen,
      );
    }
  }
}

/// A transaction pinned to a single pooled connection for its whole
/// lifetime. Obtained via [MySqlDatabase.transaction].
class MySqlTransaction implements Transaction, MySqlQueryable {
  MySqlTransaction._(this._connection, this._discard);

  final MySqlConnection _connection;

  /// Marks this transaction's pinned connection for discard, rather than
  /// return to the pool, once [MySqlDatabase.transaction] releases it --
  /// the same callback [MySqlDatabase._withConnection] hands every other
  /// caller, threaded through here so [_runChecked] can act on a
  /// statement that leaves the connection unsafe to reuse (see
  /// [_leavesConnectionUnsafeForPool]) without waiting for the whole
  /// transaction to end first.
  final void Function() _discard;

  /// Set by [MySqlDatabase.transaction] once the body it called has
  /// returned or thrown, before it commits or rolls back.
  ///
  /// The pooled connection this transaction was pinned to goes back to (or
  /// is discarded from) the pool at that same point, so a statement run on
  /// this transaction after that would not run inside this transaction at
  /// all -- it would land on whatever connection the pool hands out next,
  /// including, if the pool reused this one before it was fully released,
  /// a connection genuinely mid-COMMIT or mid-ROLLBACK for a totally
  /// unrelated caller. [query], [execute] and [insert] all route through
  /// [_runChecked], which checks this before touching the connection at
  /// all.
  bool _done = false;

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
  ///
  /// A [sql] that *fails* needs a second check for the same thing, and
  /// cannot use the shortcut above: MySQL's implicit commit on DDL fires
  /// before the statement completes, so it fires just as well when the
  /// statement goes on to fail (a table that already exists, say), and an
  /// ERR packet carries no status flags to read it off of. See
  /// [_endedByFailure].
  ///
  /// Some failures are excluded from that second check rather than folded
  /// into it -- see [_alreadyExplainsTransactionEnding].
  ///
  /// Refuses outright, before touching the connection at all, once [_done]
  /// is set: [MySqlDatabase.transaction]'s body has already returned or
  /// thrown by then, so there is no transaction left here for [sql] to
  /// run inside.
  Future<MySqlResultSets> _runChecked(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  }) async {
    if (_done) {
      throw StateError(
        'this transaction has already ended (its body returned or threw); '
        'a statement run on it now would not be part of any transaction',
      );
    }
    MySqlResultSets results;
    try {
      results = await _runQueryable(
        _connection,
        sql,
        params: params,
        args: args,
      );
    } catch (error) {
      if (!_alreadyExplainsTransactionEnding(error) &&
          await _endedByFailure()) {
        throw MySqlTransactionEndedByDdl(sql, cause: error);
      }
      rethrow;
    }
    if (_leavesConnectionUnsafeForPool(sql, results)) {
      _discard();
    }
    if (!results.inTransaction) {
      throw MySqlTransactionEndedByDdl(sql);
    }
    return results;
  }

  /// Whether the transaction is gone, asked about with a fresh `SELECT 1`
  /// rather than read off the failure that just happened -- an ERR packet
  /// carries no status flags, so there is nothing to read otherwise.
  ///
  /// Answers `false` -- "no, an ordinary failure, nothing further to do"
  /// -- both when the probe confirms the transaction is still open and
  /// when the probe itself fails. The latter matters as much as the
  /// former: a connection broken by whatever [sql] just did must not have
  /// that fact reported as a diagnostic about a `SELECT 1` nobody asked
  /// for, when [_runChecked]'s caller is about to rethrow the real error
  /// anyway.
  Future<bool> _endedByFailure() async {
    try {
      return !(await _connection.runTextQuery('SELECT 1')).inTransaction;
    } catch (_) {
      return false;
    }
  }
}

/// Whether [error]'s own type or errno already says why the transaction
/// might be gone, in a way [MySqlTransaction._endedByFailure]'s probe
/// cannot tell apart from an implicit commit: `SERVER_STATUS_IN_TRANS`
/// reads exactly the same either way, so the probe alone cannot
/// distinguish "committed" from "rolled back" -- only "gone" from "still
/// there".
///
/// [MySqlDeadlock] means the server rolled the *whole* transaction back
/// itself to break the deadlock. [MySqlLockWaitTimeout] rolls back only
/// the failing statement by default, leaving the flag set and this check
/// moot -- but `innodb_rollback_on_timeout` can turn that into a whole-
/// transaction rollback too, on a server this driver does not control.
/// Errno 1206 (`ER_LOCK_TABLE_FULL`) does the same thing by a different
/// route -- confirmed against a live server: run the lock table out of
/// memory and InnoDB discards the whole transaction, not just the
/// statement that hit the limit -- but has no dedicated exception type of
/// its own to check for, only the generic [MySqlException] that every
/// errno without one falls to, so it is matched on
/// [MySqlException.errorCode] instead of on type.
///
/// This list is not, and cannot be, exhaustive: 1206 was found by testing
/// for it, not by reasoning about which errnos behave this way, and
/// nothing rules out another one this driver has not classified doing the
/// same. Nothing here still depends on this list being complete, though
/// -- see [MySqlTransactionEndedByDdl]'s own doc comment, which no longer
/// claims a durability outcome on the path this function guards, for
/// exactly that reason. What being on this list buys is precision, not
/// correctness: an excluded error is rethrown as itself, so a caller
/// catching [MySqlDeadlock] still catches a [MySqlDeadlock], which is more
/// useful than the generic "the transaction ended, no further claim"
/// every rollback this list misses is reported as instead.
bool _alreadyExplainsTransactionEnding(Object error) =>
    error is MySqlDeadlock ||
    error is MySqlLockWaitTimeout ||
    (error is MySqlException && error.errorCode == 1206);

/// Thrown from inside a [MySqlTransaction] body when a statement -- whether
/// it succeeded or failed -- leaves the transaction no longer open.
///
/// MySQL commits a transaction implicitly when it runs DDL, such as
/// `CREATE TABLE`, and that commit happens *before* the statement itself
/// completes, so it happens whether the statement then succeeds or fails.
///
/// When [sql] *succeeded* ([cause] is `null`), that implicit commit is the
/// only way the transaction could have ended, so it is known, not guessed:
/// [sql]'s effect, and everything the transaction did before it, is
/// committed and permanent.
///
/// When [sql] *failed* ([cause] is the exception it raised), less is known.
/// All that is observable is that the transaction is gone -- an ERR packet
/// carries no status flags, so whether that happened by the same implicit
/// commit or by the server rolling the *whole* transaction back for some
/// other reason (a deadlock, a lock wait timeout on a server configured to
/// roll one back in full, or an errno this driver has not classified) is
/// not something this type can tell. It is still raised, because the
/// transaction genuinely is gone either way and the caller must not go on
/// believing it can still be rolled back -- but on this path it does not
/// claim a commit, because that claim would sometimes be false.
///
/// Either way, the `ROLLBACK` that [MySqlDatabase.transaction] sends once
/// this propagates out of the body does nothing: there is no transaction
/// left for it to act on.
final class MySqlTransactionEndedByDdl implements Exception {
  MySqlTransactionEndedByDdl(this.sql, {this.cause});

  /// The statement whose own reply -- or, when [cause] is set, whose
  /// failure -- showed the transaction had ended.
  final String sql;

  /// The exception [sql] itself raised, when this was thrown because a
  /// *failed* statement still ended the transaction. `null` when [sql]
  /// succeeded.
  ///
  /// The two cases know different amounts. When [sql] succeeded, its own
  /// reply says the flag is gone, and an implicit commit is the only way
  /// that happens -- known, not guessed, so [toString] states it as fact.
  /// When [sql] failed, all that is known is that a follow-up check (see
  /// [MySqlTransaction._endedByFailure]) found the flag gone too; an ERR
  /// packet carries no cause. [_alreadyExplainsTransactionEnding] excludes
  /// the errors already known to mean a rollback rather than a commit, but
  /// that list cannot be exhaustive -- so on this path [toString] does not
  /// say "committed": it says the transaction is gone and that which
  /// outcome happened cannot be told from here.
  final Object? cause;

  @override
  String toString() {
    final withCause = cause;
    if (withCause == null) {
      return 'MySqlTransactionEndedByDdl: running this statement implicitly '
          'committed the transaction. Everything before it is already '
          'committed and cannot be rolled back.\nSQL: $sql';
    }
    return 'MySqlTransactionEndedByDdl: the transaction is no longer open. '
        'Whether the work before this statement was committed or rolled '
        'back depends on why it ended, which this driver cannot tell from '
        'the wire.\nSQL: $sql\nCaused by: $withCause';
  }
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

/// Whether running [sql] on a pooled connection leaves that connection
/// unsafe to hand to the next, unrelated borrower.
///
/// Two independent reasons, either enough on its own:
///
/// - [sql] is a `SET` (see [_isSetStatement]). A session-scoped `SET` --
///   `time_zone`, `autocommit`, a user variable this driver has no way to
///   tell apart from one that matters -- changes state that outlives the
///   statement itself and that no later `COMMIT`, `ROLLBACK` or ordinary
///   query ever resets. Handing a connection like that back would leak
///   whatever it just changed into every later caller's session, silently:
///   `SET time_zone = '+09:00'` shifting every `TIMESTAMP` a completely
///   unrelated later borrower reads back is the concrete case this exists
///   to prevent.
/// - [results] shows autocommit off ([MySqlResultSets.autocommitEnabled]
///   is `false`). This is the symptom rather than the cause -- the cause
///   is always a `SET autocommit = 0` or equivalent, already caught by the
///   rule above -- kept as a second, independent check anyway because it
///   asks the connection's own state rather than pattern-matching [sql],
///   so it still catches whatever this driver's necessarily incomplete
///   idea of "a SET" misses.
bool _leavesConnectionUnsafeForPool(String sql, MySqlResultSets results) =>
    _isSetStatement(sql) || !results.autocommitEnabled;

/// Whether [sql] is, or starts as, a `SET` statement -- case-insensitively,
/// and after skipping any leading whitespace and `/* ... */`, `-- ` or `#`
/// comments. A `SET` preceded only by those is exactly as much a `SET` as
/// one with nothing before it: none of them run anything, so the
/// [_leavesConnectionUnsafeForPool] risk a bare `SET` poses is identical
/// either way.
bool _isSetStatement(String sql) =>
    _skipLeadingCommentsAndWhitespace(sql).toUpperCase().startsWith('SET');

/// Repeatedly strips leading whitespace, then one leading comment if
/// there is one, until neither remains -- so that several comments (or a
/// comment followed by more whitespace) in a row are all skipped, not
/// just the first.
String _skipLeadingCommentsAndWhitespace(String sql) {
  var rest = sql;
  while (true) {
    final trimmed = rest.trimLeft();
    if (trimmed.startsWith('/*')) {
      final end = trimmed.indexOf('*/');
      // An unterminated block comment is not valid SQL either way; giving
      // up here just means the "SET" check below sees whatever text is
      // left, which is no worse than not skipping the comment at all.
      if (end == -1) return trimmed;
      rest = trimmed.substring(end + 2);
      continue;
    }
    if (trimmed.startsWith('--') || trimmed.startsWith('#')) {
      final newline = trimmed.indexOf('\n');
      if (newline == -1) return '';
      rest = trimmed.substring(newline + 1);
      continue;
    }
    return trimmed;
  }
}

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
