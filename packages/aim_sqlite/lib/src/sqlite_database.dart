import 'dart:async';

import 'package:aim_database/aim_database.dart';
import 'package:aim_sqlite/src/reader_pool.dart';
import 'package:aim_sqlite/src/routing.dart';
import 'package:aim_sqlite/src/sqlite_exception.dart';
import 'package:aim_sqlite/src/sqlite_options.dart';
import 'package:aim_sqlite/src/sqlite_stats.dart';
import 'package:aim_sqlite/src/types/value_encoder.dart';
import 'package:aim_sqlite/src/worker/handle.dart';
import 'package:aim_sqlite/src/worker/protocol.dart';

/// Marks the zone a transaction body runs in, so that a call which would
/// wait for that very transaction can be refused instead of hanging.
///
/// The value is the transaction itself rather than a bare flag, because
/// the zone is broader than the calls that have to be refused: it reaches
/// other databases, and it outlives the body. Both are narrowed down by
/// asking the transaction, in [SqliteDatabase._insideOwnTransactionBody].
final Object _txKey = Object();

/// The id of the one request the driver makes on its own account, before the
/// caller's first. Negative like the worker handle's own close request, which
/// is what keeps it clear of a caller's: those are numbered from zero up.
const int _walIndexRequestId = -2;

/// A SQLite database, reached over dart:ffi from worker isolates.
///
/// SQLite's C API blocks the thread it is called on, so every statement runs
/// on an isolate of its own rather than on the one serving requests.
///
/// Writes go to a single writer, because SQLite allows one at a time. Reads
/// go to one of [SqliteOptions.readers] connections opened read-only, each on
/// its own isolate, so they run alongside each other and alongside the
/// writer: in WAL mode a write never blocks a read, which sees the snapshot
/// from before it instead. Which connection a statement lands on is decided
/// by its leading keyword and then checked again on the connection itself,
/// so a write that the keyword did not give away is still never stepped by a
/// reader.
///
/// **Await a write before reading what it wrote.** A read goes to its own
/// connection instead of queueing behind the writes, so a write and a read
/// started in that order are two statements on two connections and the read
/// may well win: it can return the value from before the write, or fail with
/// "no such table" when the write was the CREATE TABLE. Awaiting the write
/// is all it takes. This is a different thing from the snapshot a reader
/// takes while a transaction holds the writer, which is deliberate, and
/// which awaiting cannot change from outside the transaction.
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
  SqliteDatabase._(this._writer, this._readers);

  /// The one connection that may write. SQLite allows exactly one writer at
  /// a time, so serialising through a single isolate is not a limitation.
  final SqliteWorkerHandle _writer;

  /// The read-only connections. Empty when there is no second connection to
  /// be had, and then reads go to the writer as well.
  final ReaderPool _readers;

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
  ///
  /// [busyTimeout] bounds SQLite waiting for a lock on the file;
  /// [acquireTimeout] bounds this driver waiting for a read-only connection
  /// to come free. A read therefore costs at worst the two of them plus
  /// however long the statement itself takes. Neither bounds a statement
  /// that is running, and neither bounds the writer's queue --
  /// [SqliteOptions.acquireTimeout] says why.
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
    // The readers come up only once the writer has the database ready for
    // them, because a read-only connection can neither create a database nor
    // put one in WAL mode, and fails with SQLITE_CANTOPEN rather than making
    // do.
    final ReaderPool readerPool;
    try {
      if (options.readers > 0) await _createWalIndex(writer);
      readerPool = await ReaderPool.spawn(
        path,
        count: options.readers,
        options: options,
      );
    } on Object {
      // Otherwise a database that could not finish opening leaves its writer
      // isolate running with nobody left holding it.
      await writer.close();
      rethrow;
    }
    return SqliteDatabase._(writer, readerPool);
  }

  /// Reads the schema on [writer], which is what makes the WAL index exist.
  ///
  /// A read-only connection cannot read a WAL database without the WAL index
  /// -- the `-shm` file -- and cannot create one: it is shared, mutable
  /// state, so only a connection that may write the database may write it.
  /// Nothing has created it at this point, because putting the database in
  /// WAL mode writes the header and never reads a page; what brings the
  /// index into being is the first connection to touch the database. So the
  /// writer touches it here. Without that, every read on a database nothing
  /// had yet written to would fail with SQLITE_CANTOPEN.
  static Future<void> _createWalIndex(SqliteWorkerHandle writer) async {
    final response = await writer.send(
      const SqliteRunRequest(
        _walIndexRequestId,
        'SELECT count(*) FROM sqlite_schema',
        positional: [],
        named: {},
        wantRows: false,
        requireReadOnly: false,
      ),
    );
    // Rethrown so that a database the writer cannot even read the schema of
    // fails to open, rather than opening with readers that cannot read.
    if (response case SqliteErrorResponse(:final error)) throw error;
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  }) {
    // Ahead of the routing, because a call made from inside a transaction
    // body has to be refused whichever connection it would have landed on.
    if (_insideOwnTransactionBody) return _refuseCallOnDatabase();
    if (_readers.size == 0 || routeFor(sql) == SqliteRoute.writer) {
      return _queryOnWriter(sql, params, args);
    }
    return _queryOnReader(sql, params, args);
  }

  @override
  Future<int> execute(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  }) {
    if (_insideOwnTransactionBody) return _refuseCallOnDatabase();
    // Straight to the writer without asking [routeFor]. Nobody sends a read
    // through execute(), which reports a row count and no rows, and putting
    // one on a reader would buy nothing.
    return _serialized(() async {
      final result = await _runOnWriter(sql, params, args, wantRows: false);
      return result.affected;
    });
  }

  /// Runs [fn] inside a transaction, holding the writer for as long as it
  /// takes, and commits when [fn] returns or rolls back when it throws.
  ///
  /// `BEGIN IMMEDIATE`: the write lock is taken up front rather than at the
  /// transaction's first write, where SQLite could still refuse it. A
  /// transaction that cannot have the lock therefore fails before [fn]
  /// runs at all.
  ///
  /// **[fn] must go through the [Transaction] it is handed, not through the
  /// database.** [query], [execute] and [transaction] called on the
  /// database from inside [fn] would each wait for the transaction they are
  /// running inside, which cannot finish until [fn] returns; they are
  /// refused with a [StateError] rather than left to hang. Statements on
  /// the [Transaction] go to the same connection whether they read or
  /// write, because a read inside a transaction has to see the
  /// transaction's own uncommitted writes.
  ///
  /// A call from anywhere else -- another request served while [fn] runs --
  /// waits its turn and goes through after the commit or the rollback. It
  /// never joins the transaction, so a rollback cannot take it along.
  ///
  /// The [Transaction] stops working as soon as [fn] returns: by then the
  /// writer belongs to whoever was waiting for it.
  @override
  Future<T> transaction<T>(Future<T> Function(Transaction tx) fn) {
    if (_insideOwnTransactionBody) return _refuseCallOnDatabase();
    return _serialized(() => _runTransaction(fn));
  }

  /// How busy the connections are, for a caller that wants to watch it.
  SqliteStats get stats => SqliteStats(
    readers: _readers.size,
    busyReaders: _readers.busy,
    queued: _readers.queued,
    writerBusy: _writer.busy,
  );

  @override
  Future<void> close() {
    _closed = true;
    // Everything is asked to stop before any of it is waited for, so the
    // readers are not left sitting idle while the writer finishes what it
    // was running. Each handle hands the same future back every time, so a
    // second close still waits for the isolates to actually be gone rather
    // than returning while the first one is mid-flight.
    return Future.wait([_writer.close(), _readers.close()]);
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
  ///
  /// That order is the writer's order, and covers only what comes through
  /// here: every write, every transaction, and a read that had nowhere else
  /// to go. A read on a reader does not queue -- it would be waiting for a
  /// transaction that cannot block it -- so it is not ordered against the
  /// writes waiting here. [SqliteDatabase] says what that leaves a caller
  /// able to rely on.
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
    //
    // Through Future.sync, the same shape ReaderPool._lend uses for the
    // same reason: an action that threw where it stands would otherwise
    // never reach [release], leaving [_tail] an uncompleted future that
    // every later call on this database waits on forever, with nothing
    // anywhere to say why. Every action here is an async closure today, so
    // that is latent rather than live -- and unreachable now.
    if (previous == null) return Future.sync(action).whenComplete(release);
    return previous.then((_) => action()).whenComplete(release);
  }

  /// True while the calling code is inside the body of a transaction of
  /// this database's that has not finished yet.
  ///
  /// Both halves of that narrow it down from what the zone alone says, and
  /// a call refused on either count would be refused with nothing to wait
  /// for and no way around it:
  ///
  /// - Scoped to this database, because the queue a body is holding is
  ///   this database's queue, so a call on another one cannot deadlock on
  ///   it.
  /// - Scoped to a transaction still running, because a zone value travels
  ///   with everything the body ever scheduled and not only with its
  ///   synchronous extent. A timer or a stream listener set up inside the
  ///   body still finds the marker when it fires, long after the commit.
  ///   [SqliteTransaction._done] is set before the commit, so this still
  ///   covers the whole body.
  bool get _insideOwnTransactionBody {
    final marker = Zone.current[_txKey];
    return marker is SqliteTransaction &&
        identical(marker._database, this) &&
        !marker._done;
  }

  /// Refuses a call that would queue behind the transaction the calling
  /// code is itself inside. Queuing it would wait for a lease that cannot
  /// come free until the body returns -- with no timeout, and nothing in
  /// the stack to say why. Delivered as a failed future, the way [_run]
  /// delivers its refusal on a closed database.
  Future<T> _refuseCallOnDatabase<T>() => Future.error(
    StateError(
      'use tx inside a transaction: this call on the database would wait '
      'for the transaction it is running inside to finish',
    ),
  );

  /// Runs one transaction. Called with the queue held, so nothing else can
  /// reach the connection between the BEGIN and the COMMIT.
  Future<T> _runTransaction<T>(Future<T> Function(Transaction tx) fn) async {
    if (_closed) throw StateError('SqliteDatabase is closed');
    await _control(SqliteBeginRequest(_nextRequestId++));
    final tx = SqliteTransaction._(this);
    try {
      // The zone marker is the only thing that can tell a call made from
      // inside the body from one made by other code running concurrently:
      // it travels with the body's own asynchronous continuations, and a
      // concurrent caller has no way to end up holding it. It outlives the
      // body as well, which is why reading it also asks whether the
      // transaction is still open.
      final result = await runZoned(() => fn(tx), zoneValues: {_txKey: tx});
      tx._done = true;
      await _control(SqliteCommitRequest(_nextRequestId++));
      return result;
    } on Object catch (error) {
      tx._done = true;
      // A failed COMMIT comes through here too. SQLite sometimes leaves the
      // transaction open when it cannot commit one and sometimes rolls it
      // back itself first; the rollback below tells those apart instead of
      // this having to guess.
      await _rollback(error);
      rethrow;
    }
  }

  /// Rolls back the transaction that [cause] stopped.
  ///
  /// Returns normally when the rollback worked, and also when SQLite
  /// refused it because there was nothing left to roll back -- the worker
  /// sorts that case out for itself, since it is the ordinary aftermath of
  /// a COMMIT that SQLite gave up on. The caller then rethrows [cause]
  /// with the stack trace it was thrown with.
  ///
  /// What is left is a rollback that really failed, and [cause] is folded
  /// into its message rather than dropped: it is the only record of why
  /// anything was being rolled back. A refusal that left the transaction
  /// open stays a [SqliteException], so its extended result code still
  /// describes the rollback; a rollback that never reached the connection
  /// at all -- the isolate is gone, the database was closed -- has no
  /// result code to keep.
  Future<void> _rollback(Object cause) async {
    try {
      await _control(SqliteRollbackRequest(_nextRequestId++));
    } on SqliteException catch (error) {
      throw SqliteException(
        extendedResultCode: error.extendedResultCode,
        message: '${error.message} (rolling back after: $cause)',
        sql: error.sql,
      );
    } on Object catch (error) {
      // A StateError reads better by its message than by its toString once
      // it is quoted inside another one, and StateError is what both the
      // worker handle and the closed-database check throw here.
      throw StateError(
        '${error is StateError ? error.message : error} '
        '(rolling back after: $cause)',
      );
    }
  }

  /// Sends one of the transaction control requests and throws unless the
  /// worker reports that it ran. There is nothing to hand back: none of
  /// them produces rows or reports a row count.
  ///
  /// Anything other than a rows response is refused rather than taken for
  /// success. A BEGIN counted as run without having run would leave a
  /// "transaction" that commits statement by statement, and a ROLLBACK
  /// that rolls nothing back.
  Future<void> _control(SqliteRequest request) async {
    final response = await _writer.send(request);
    if (response case SqliteErrorResponse(:final error)) throw error;
    if (response is! SqliteRowsResponse) {
      throw StateError(
        'the SQLite worker answered ${request.runtimeType} with '
        '${response.runtimeType}, so it cannot be taken to have run',
      );
    }
  }

  /// Runs a read on the writer, queueing for it like anything else does.
  Future<List<Map<String, dynamic>>> _queryOnWriter(
    String sql,
    Map<String, dynamic>? params,
    List<dynamic>? args,
  ) => _serialized(() async {
    final result = await _runOnWriter(sql, params, args, wantRows: true);
    return result.rows;
  });

  /// Runs a read on one of the read-only connections.
  ///
  /// The leading keyword saying this reads is only the first of the two
  /// stages. The reader prepares the whole batch and checks
  /// sqlite3_stmt_readonly on every statement in it before stepping any of
  /// them, so a write that got this far -- a `WITH ... INSERT`, or a batch
  /// led by a SELECT with an INSERT further along -- comes back unrun and is
  /// sent to the writer instead.
  ///
  /// Preparing the batch up front has a cost that comes with the property:
  /// a statement that only makes sense once an earlier one in the same batch
  /// has run cannot be prepared at all, so `SELECT 1; CREATE TEMP TABLE t AS
  /// SELECT 1; SELECT * FROM t` fails here with "no such table" rather than
  /// being handed to the writer, which would have managed it. Preparing them
  /// one at a time instead would mean stepping a statement before knowing
  /// whether the batch writes, which is the whole thing being bought.
  ///
  /// Not queued through [_serialized]. A read on a reader never touches the
  /// writer, so waiting for the queue would make it wait for a transaction
  /// that cannot block it: in WAL mode it reads the snapshot from before
  /// that transaction. The hand-off to the writer does queue, because by
  /// then it is a write like any other.
  Future<List<Map<String, dynamic>>> _queryOnReader(
    String sql,
    Map<String, dynamic>? params,
    List<dynamic>? args,
  ) async {
    if (_closed) throw StateError('SqliteDatabase is closed');
    final request = _request(
      sql,
      params,
      args,
      wantRows: true,
      requireReadOnly: true,
    );
    // The pool lends a free reader where it stands, so the statement is on
    // the isolate's port before this returns rather than a microtask later.
    // When they are all busy it waits, and only that wait is bounded by
    // acquireTimeout.
    final response = await _readers.withReader(
      (reader) => reader.send(request),
      sql: sql,
    );
    switch (response) {
      case SqliteRowsResponse(:final rows):
        return rows;
      case SqliteErrorResponse(:final error):
        throw error;
      case SqliteNotReadOnlyResponse():
        // Nothing ran, so this is not a half-run batch being retried. The
        // writer is sent it without requireReadOnly, which is also what lets
        // it go back to preparing the batch a statement at a time.
        return _queryOnWriter(sql, params, args);
    }
  }

  /// Sends one statement request to the writer. Its connection is open
  /// read-write, so nothing there is ever handed back as a write.
  Future<SqliteRowsResponse> _runOnWriter(
    String sql,
    Map<String, dynamic>? params,
    List<dynamic>? args, {
    required bool wantRows,
  }) async {
    if (_closed) throw StateError('SqliteDatabase is closed');
    final response = await _writer.send(
      _request(sql, params, args, wantRows: wantRows, requireReadOnly: false),
    );
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

  /// Builds one statement request.
  ///
  /// Parameters are encoded here, in the caller's own stack, so a value with
  /// no SQLite representation is rejected before it reaches an isolate.
  SqliteRunRequest _request(
    String sql,
    Map<String, dynamic>? params,
    List<dynamic>? args, {
    required bool wantRows,
    required bool requireReadOnly,
  }) => SqliteRunRequest(
    _nextRequestId++,
    sql,
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
    requireReadOnly: requireReadOnly,
  );
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
  ///
  /// Also what bounds the refusal in
  /// [SqliteDatabase._insideOwnTransactionBody], so moving when this is
  /// set moves how long a call the body scheduled stays refused.
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
    final result = await _database._runOnWriter(
      sql,
      params,
      args,
      wantRows: true,
    );
    return result.rows;
  }

  @override
  Future<int> execute(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  }) async {
    _checkOpen();
    final result = await _database._runOnWriter(
      sql,
      params,
      args,
      wantRows: false,
    );
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

/// True for a database that lives only in memory: `:memory:`, or either of
/// the `file:` URI spellings of one.
///
/// Such a database is private to the connection that opened it, so a reader
/// would not be sharing it -- it would open an empty one of its own.
bool _isMemoryPath(String path) {
  if (path == ':memory:') return true;
  if (!path.startsWith('file:')) return false;
  // What SQLite compares against ":memory:" is the filename, which is what
  // is left of the URI once the query and the fragment are cut off: it reads
  // `file::memory:` as a memory database, and a file that happens to be
  // named ":memory:" inside some directory as a file.
  final rest = path.substring('file:'.length);
  if (rest.split('?').first.split('#').first == ':memory:') return true;
  // `mode` is read as a parameter of its own rather than searched for as a
  // substring, which would call `file:x?other_mode=memory_foo` -- an
  // ordinary file -- a memory database and leave it with no readers.
  return Uri.tryParse(path)?.queryParameters['mode'] == 'memory';
}
