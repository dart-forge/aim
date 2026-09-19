import 'dart:isolate';

import 'package:aim_sqlite/src/ffi/bindings.dart';
import 'package:aim_sqlite/src/sqlite_options.dart';
import 'package:aim_sqlite/src/worker/connection.dart';
import 'package:aim_sqlite/src/worker/protocol.dart';

/// The message Isolate.spawn carries. Everything in it is sendable.
class SqliteWorkerConfig {
  const SqliteWorkerConfig({
    required this.ready,
    required this.path,
    required this.readOnly,
    required this.libraryPath,
    required this.busyTimeout,
    required this.synchronous,
  });

  /// Where the handshake goes, and every response after it.
  final SendPort ready;

  final String path;
  final bool readOnly;
  final String? libraryPath;
  final Duration busyTimeout;
  final SqliteSynchronous synchronous;
}

/// Runs in its own isolate: opens one connection, answers requests, and is
/// the only place SQLite is touched.
///
/// The library is opened here rather than passed in: a DynamicLibrary cannot
/// cross a SendPort. dlopen is reference counted, so this is cheap.
Future<void> sqliteWorkerMain(SqliteWorkerConfig config) async {
  final SqliteConnection connection;
  try {
    connection = SqliteConnection.open(
      SqliteLibrary.open(libraryPath: config.libraryPath),
      config.path,
      readOnly: config.readOnly,
      busyTimeout: config.busyTimeout,
      synchronous: config.synchronous,
    );
  } on Object catch (error) {
    // The handshake carries the failure in place of a port, so the parent's
    // open() throws it instead of waiting for a worker that will never
    // answer.
    config.ready.send(error);
    return;
  }

  // Requests arrive here; responses go back on the port the handshake came
  // in on. One port each way is enough, because the request id is what pairs
  // a response with its request -- a reply port per request would only be
  // more to clean up.
  final requests = ReceivePort();
  config.ready.send(requests.sendPort);

  await for (final message in requests) {
    final request = message as SqliteRequest;
    switch (request) {
      case SqliteRunRequest():
        config.ready.send(_answer(connection, request));
      case SqliteBeginRequest():
        config.ready.send(_control(request, connection.begin));
      case SqliteCommitRequest():
        config.ready.send(_control(request, connection.commit));
      case SqliteRollbackRequest():
        config.ready.send(_control(request, connection.rollback));
      case SqliteCloseRequest():
        connection.close();
        // Nothing is listening any more, so the isolate runs out of work and
        // exits; Isolate.spawn's onExit is what tells the parent it is gone.
        requests.close();
    }
  }
}

/// Runs one of the transaction control statements. They have no rows and no
/// row count to report, so the answer only says whether it worked.
SqliteResponse _control(SqliteRequest request, void Function() statement) {
  try {
    statement();
    return SqliteRowsResponse(request.id, const [], 0);
  } on Object catch (error) {
    // Same reason as _answer: the caller has to hear how it went, and an
    // error thrown out of here would take the isolate down with it.
    return SqliteErrorResponse(request.id, error);
  }
}

SqliteResponse _answer(SqliteConnection connection, SqliteRunRequest request) {
  try {
    final result = connection.run(
      request.sql,
      positional: request.positional,
      named: request.named,
      wantRows: request.wantRows,
      requireReadOnly: request.requireReadOnly,
    );
    if (result == null) return SqliteNotReadOnlyResponse(request.id);
    return SqliteRowsResponse(request.id, result.rows, result.affected);
  } on Object catch (error) {
    // Everything, including an ArgumentError from binding: the caller asked
    // for this statement and has to hear how it went, and an error thrown
    // out of here would take the isolate down with it.
    return SqliteErrorResponse(request.id, error);
  }
}
