import 'dart:async';

import 'package:aim_database/aim_database.dart';
import 'package:aim_sqlite/src/sqlite_exception.dart';
import 'package:aim_sqlite/src/sqlite_options.dart';
import 'package:aim_sqlite/src/types/value_encoder.dart';
import 'package:aim_sqlite/src/worker/handle.dart';
import 'package:aim_sqlite/src/worker/protocol.dart';

/// A SQLite database, reached over dart:ffi from worker isolates.
///
/// SQLite's C API blocks the thread it is called on, so every statement runs
/// on an isolate of its own rather than on the one serving requests.
///
/// One call may run several statements, and the counts and rows are reported
/// as [Database] describes. Parameters, though, only reach the first
/// statement of such a batch: a later one carrying a placeholder is refused
/// rather than left holding a NULL that SQLite would store without a word.
///
/// That refusal is not a rollback. Statements run one at a time, so the ones
/// ahead of the refused statement have already been applied and committed
/// when the [ArgumentError] arrives; running the same call again would apply
/// them a second time. Wrap a batch that must be all or nothing in a
/// [transaction].
class SqliteDatabase extends Database {
  SqliteDatabase._(this._writer);

  /// The one connection that may write. SQLite allows exactly one writer at
  /// a time, so serialising through a single isolate is not a limitation.
  final SqliteWorkerHandle _writer;

  /// Numbered from zero up, which is what pairs a response with its request.
  int _nextRequestId = 0;

  /// The tail of the queue that a transaction holds; see [_serialized].
  ///
  /// Null while nothing is queued, so that a call on an idle database gets
  /// its request onto the port before returning rather than a microtask
  /// later -- [close] leans on that to wait for a statement already sent
  /// instead of refusing it.
  Future<void>? _tail;

  bool _closed = false;

  /// Opens [path] and starts the isolates that talk to it.
  ///
  /// [path] may be a file, `:memory:`, or a `file:` URI. A memory database
  /// is private to its connection, so there is nothing for readers to share
  /// and [readers] is forced to 0.
  static Future<SqliteDatabase> open(
    String path, {
    int readers = 4,
    Duration busyTimeout = const Duration(seconds: 5),
    SqliteSynchronous synchronous = SqliteSynchronous.full,
    String? libraryPath,
    Duration acquireTimeout = const Duration(seconds: 30),
  }) async {
    final options = SqliteOptions(
      // A negative count is still handed to the constructor, so asking for
      // one stays an error instead of being quietly clamped away.
      readers: _isMemoryPath(path) && readers > 0 ? 0 : readers,
      busyTimeout: busyTimeout,
      synchronous: synchronous,
      libraryPath: libraryPath,
      acquireTimeout: acquireTimeout,
    );
    final writer = await SqliteWorkerHandle.spawn(
      path,
      readOnly: false,
      options: options,
    );
    return SqliteDatabase._(writer);
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  }) => _serialized(() async {
    final result = await _run(sql, params, args, wantRows: true);
    return result.rows;
  });

  @override
  Future<int> execute(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  }) => _serialized(() async {
    final result = await _run(sql, params, args, wantRows: false);
    return result.affected;
  });

  /// Runs [fn] inside a transaction, holding the writer for as long as it
  /// takes, and commits when [fn] returns or rolls back when it throws.
  ///
  /// `BEGIN IMMEDIATE`: the write lock is taken up front rather than at the
  /// transaction's first write, where SQLite could still refuse it.
  ///
  /// A [query] or [execute] on the database while [fn] is running waits and
  /// goes through after the commit or the rollback. It never joins the
  /// transaction, so a rollback cannot take it along. Statements on the
  /// [Transaction] itself go to the same connection whether they read or
  /// write, because a read inside a transaction has to see the
  /// transaction's own uncommitted writes.
  ///
  /// The [Transaction] stops working as soon as [fn] returns: by then the
  /// writer belongs to whoever was waiting for it.
  @override
  Future<T> transaction<T>(Future<T> Function(Transaction tx) fn) =>
      _serialized(() => _runTransaction(fn));

  @override
  Future<void> close() {
    _closed = true;
    // The handle hands the same future back every time, so a second close
    // still waits for the isolate to actually be gone rather than returning
    // while the first one is mid-flight.
    return _writer.close();
  }

  /// Runs [action] once everything already queued has finished, and keeps
  /// the queue to itself until it is done.
  ///
  /// This is the whole of the rule that a transaction owns the writer. A
  /// transaction runs as one action, so a statement handed to the database
  /// while its body is running lands behind the COMMIT or the ROLLBACK
  /// instead of inside the transaction, where it would be committed -- or
  /// thrown away -- on somebody else's terms. One queue, so those waiting
  /// statements also keep the order they arrived in.
  Future<T> _serialized<T>(Future<T> Function() action) {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    void release() {
      // Only while the queue still ends with us: an emptied queue has to go
      // back to null, or every later call would wait a microtask on a
      // future that is already done.
      if (_tail == done.future) _tail = null;
      done.complete();
    }

    // Nothing to wait for, so [action] starts here instead of a microtask
    // later, which is what puts its request on the port before returning.
    if (previous == null) return action().whenComplete(release);
    return previous.then((_) => action()).whenComplete(release);
  }

  /// Runs one transaction. Called with the queue held, so nothing else can
  /// reach the connection between the BEGIN and the COMMIT.
  Future<T> _runTransaction<T>(Future<T> Function(Transaction tx) fn) async {
    if (_closed) throw StateError('SqliteDatabase is closed');
    await _control(SqliteBeginRequest(_nextRequestId++));
    final tx = SqliteTransaction._(this);
    try {
      final result = await fn(tx);
      tx._done = true;
      await _control(SqliteCommitRequest(_nextRequestId++));
      return result;
    } on Object catch (error) {
      tx._done = true;
      // A failed COMMIT comes through here too: SQLite leaves the
      // transaction open when it cannot commit one, so that still has to be
      // rolled back.
      await _rollback(error);
      rethrow;
    }
  }

  /// Rolls back the transaction that [cause] stopped.
  ///
  /// Returns normally when the rollback worked, leaving the caller to
  /// rethrow [cause] with the stack trace it was thrown with.
  ///
  /// A ROLLBACK that SQLite itself refuses is the worse of the two
  /// failures: the connection is left inside an open transaction, and
  /// nothing says so until the next BEGIN IMMEDIATE is refused too. So that
  /// is what gets thrown, in [cause]'s place -- carrying [cause]'s text,
  /// because "the rollback failed" never says what was being rolled back.
  ///
  /// A rollback that could not even be sent is left to throw on its own:
  /// the isolate is gone, which is what [cause] will say as well, and its
  /// connection went with it, so no transaction is left open to warn about.
  Future<void> _rollback(Object cause) async {
    try {
      await _control(SqliteRollbackRequest(_nextRequestId++));
    } on SqliteException catch (error) {
      throw SqliteException(
        extendedResultCode: error.extendedResultCode,
        message: '${error.message} (while rolling back after: $cause)',
        sql: error.sql,
      );
    }
  }

  /// Sends one of the transaction control requests and throws whatever the
  /// worker reported. There is nothing to hand back: none of them produces
  /// rows or reports a row count.
  Future<void> _control(SqliteRequest request) async {
    final response = await _writer.send(request);
    if (response case SqliteErrorResponse(:final error)) throw error;
  }

  Future<SqliteRowsResponse> _run(
    String sql,
    Map<String, dynamic>? params,
    List<dynamic>? args, {
    required bool wantRows,
  }) async {
    if (_closed) throw StateError('SqliteDatabase is closed');
    final request = SqliteRunRequest(
      _nextRequestId++,
      sql,
      // Encoded here so a value with no SQLite representation is rejected in
      // the caller's own stack rather than inside an isolate.
      positional: [
        for (var i = 0; i < (args?.length ?? 0); i++)
          encodeValue(args![i], parameter: 'args[$i]'),
      ],
      named: {
        if (params != null)
          for (final entry in params.entries)
            entry.key: encodeValue(
              entry.value,
              parameter: 'params["${entry.key}"]',
            ),
      },
      wantRows: wantRows,
      // Everything goes to the writer for now; routing arrives with the
      // read-only isolates.
      requireReadOnly: false,
    );

    final response = await _writer.send(request);
    switch (response) {
      case SqliteRowsResponse():
        return response;
      case SqliteErrorResponse(:final error):
        throw error;
      case SqliteNotReadOnlyResponse():
        throw StateError(
          'the writer isolate refused "$sql" as a write, which only a '
          'read-only connection is allowed to do',
        );
    }
  }
}

/// Statements bound to one open transaction, and so to the writer isolate
/// that is holding it. Reached as a [Transaction], from the body of
/// [SqliteDatabase.transaction].
class SqliteTransaction implements Transaction {
  SqliteTransaction._(this._database);

  final SqliteDatabase _database;

  /// Set once the body has returned. The writer goes back to whoever was
  /// waiting for it then, so a statement sent after that would run outside
  /// the transaction -- committed on its own, or swept into the next one.
  bool _done = false;

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  }) async {
    _checkOpen();
    // Straight to the connection, past the queue this transaction holds:
    // joining the queue here would mean waiting for itself.
    final result = await _database._run(sql, params, args, wantRows: true);
    return result.rows;
  }

  @override
  Future<int> execute(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  }) async {
    _checkOpen();
    final result = await _database._run(sql, params, args, wantRows: false);
    return result.affected;
  }

  void _checkOpen() {
    if (_done) {
      throw StateError(
        'the transaction has ended; a statement on it now would run outside '
        'the transaction',
      );
    }
  }
}

/// True for a database that lives only in memory: `:memory:`, or a `file:`
/// URI asking for `mode=memory`.
bool _isMemoryPath(String path) =>
    path == ':memory:' ||
    (path.startsWith('file:') && path.contains('mode=memory'));
