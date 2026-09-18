import 'package:aim_database/aim_database.dart';
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
/// transaction.
class SqliteDatabase extends Database {
  SqliteDatabase._(this._writer);

  /// The one connection that may write. SQLite allows exactly one writer at
  /// a time, so serialising through a single isolate is not a limitation.
  final SqliteWorkerHandle _writer;

  /// Numbered from zero up, which is what pairs a response with its request.
  int _nextRequestId = 0;

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
  }) async {
    final result = await _run(sql, params, args, wantRows: true);
    return result.rows;
  }

  @override
  Future<int> execute(
    String sql, {
    Map<String, dynamic>? params,
    List<dynamic>? args,
  }) async {
    final result = await _run(sql, params, args, wantRows: false);
    return result.affected;
  }

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction tx) fn) =>
      throw UnimplementedError(
        'SqliteDatabase.transaction is not implemented yet',
      );

  @override
  Future<void> close() {
    _closed = true;
    // The handle hands the same future back every time, so a second close
    // still waits for the isolate to actually be gone rather than returning
    // while the first one is mid-flight.
    return _writer.close();
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

/// True for a database that lives only in memory: `:memory:`, or a `file:`
/// URI asking for `mode=memory`.
bool _isMemoryPath(String path) =>
    path == ':memory:' ||
    (path.startsWith('file:') && path.contains('mode=memory'));
