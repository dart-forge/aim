import 'dart:async';
import 'dart:isolate';

import 'package:aim_sqlite/src/sqlite_options.dart';
import 'package:aim_sqlite/src/worker/protocol.dart';
import 'package:aim_sqlite/src/worker/worker.dart';

/// The id of the handle's own close request. Every other request is numbered
/// by the caller from zero up, so this cannot collide with one.
const int _closeRequestId = -1;

/// One worker isolate, seen from the main isolate.
///
/// The only class that holds a SendPort: keeping isolate plumbing here is
/// what lets SqliteDatabase stay free of dart:isolate.
class SqliteWorkerHandle {
  SqliteWorkerHandle._(this._responses);

  /// Everything the worker sends arrives here: its request port first, then
  /// one response per request, then a null when the isolate exits.
  final ReceivePort _responses;

  final Map<int, Completer<SqliteResponse>> _pending = {};

  /// Completes once the worker has its connection open, or with whatever
  /// stopped it from opening one.
  final Completer<void> _ready = Completer<void>();

  /// Completes when the isolate is gone, however it went.
  final Completer<void> _exited = Completer<void>();

  SendPort? _requests;
  bool _stopping = false;

  /// Spawns the isolate, waits for its handshake, and rethrows whatever the
  /// isolate reported if the connection could not be opened.
  static Future<SqliteWorkerHandle> spawn(
    String path, {
    required bool readOnly,
    required SqliteOptions options,
  }) async {
    final responses = ReceivePort();
    final handle = SqliteWorkerHandle._(responses);
    responses.listen(handle._onMessage);
    try {
      await Isolate.spawn(
        sqliteWorkerMain,
        SqliteWorkerConfig(
          ready: responses.sendPort,
          path: path,
          readOnly: readOnly,
          libraryPath: options.libraryPath,
          busyTimeout: options.busyTimeout,
          synchronous: options.synchronous,
        ),
        // Arrives as a null on the same port, so a worker that dies cannot
        // leave a caller waiting for a response forever.
        onExit: responses.sendPort,
        debugName: 'aim_sqlite ${readOnly ? 'reader' : 'writer'}',
      );
    } on Object {
      responses.close();
      rethrow;
    }
    await handle._ready.future;
    return handle;
  }

  /// True while a request is outstanding.
  bool get busy => _pending.isNotEmpty;

  /// Sends [request] and completes with the matching response. Responses
  /// arrive on one port and are matched by [SqliteRequest.id].
  Future<SqliteResponse> send(SqliteRequest request) {
    final port = _requests;
    if (port == null || _stopping) {
      return Future.error(StateError('the SQLite worker isolate is stopped'));
    }
    final completer = Completer<SqliteResponse>();
    _pending[request.id] = completer;
    port.send(request);
    return completer.future;
  }

  /// Asks the isolate to close its connection and stop. Waits for the
  /// request in flight, because an FFI call cannot be interrupted.
  Future<void> close() {
    if (_stopping) return _exited.future;
    _stopping = true;
    // The worker reads its port in order, so it only sees this once it has
    // answered whatever it was running -- and the exit notice lands behind
    // that answer, which is what makes waiting for it enough.
    _requests?.send(const SqliteCloseRequest(_closeRequestId));
    return _exited.future;
  }

  void _onMessage(Object? message) {
    if (!_ready.isCompleted) {
      switch (message) {
        case final SendPort port:
          _requests = port;
          _ready.complete();
        case null:
          _finish(
            StateError(
              'the SQLite worker isolate exited before it opened its '
              'connection',
            ),
          );
        default:
          // The worker sends the failure itself when it cannot open the
          // connection.
          _finish(message);
      }
      return;
    }
    if (message == null) {
      _finish(StateError('the SQLite worker isolate exited'));
      return;
    }
    final response = message as SqliteResponse;
    _pending.remove(response.id)?.complete(response);
  }

  /// The isolate is gone. Nothing else will arrive, so every caller still
  /// waiting has to hear about it.
  void _finish(Object error) {
    _requests = null;
    _stopping = true;
    _responses.close();
    if (!_ready.isCompleted) _ready.completeError(error);
    final waiting = _pending.values.toList();
    _pending.clear();
    for (final completer in waiting) {
      completer.completeError(error);
    }
    if (!_exited.isCompleted) _exited.complete();
  }
}
