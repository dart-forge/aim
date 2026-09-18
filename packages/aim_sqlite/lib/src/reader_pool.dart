import 'dart:async';
import 'dart:collection';

import 'package:aim_sqlite/src/sqlite_exception.dart';
import 'package:aim_sqlite/src/sqlite_options.dart';
import 'package:aim_sqlite/src/worker/handle.dart';

/// What a read is failed with once the pool is closing, whether it was
/// already queued or arrives afterwards.
///
/// Deliberately the same words SqliteDatabase refuses a call on a closed
/// database with: which of the two a read gets depends only on how far it
/// had got when close came, and that is not a difference a caller can act
/// on.
const _closedMessage = 'SqliteDatabase is closed';

/// The read-only connections, one worker isolate each, and the reads waiting
/// for one of them.
///
/// Every reader is spawned when the database is opened and lives until it is
/// closed, so there is nothing here about evicting an idle connection, about
/// a maximum lifetime, or about checking a connection before lending it: the
/// only questions this answers are which reader is free and how long a read
/// waits for one.
class ReaderPool {
  ReaderPool._(List<SqliteWorkerHandle> readers, this._acquireTimeout)
    : _readers = readers,
      _idle = List.of(readers);

  /// Spawns [count] read-only connections on [path].
  ///
  /// Only ever called once the writer is up. A read-only connection cannot
  /// create a database, and SQLite refuses one asked for a file that is not
  /// there with SQLITE_CANTOPEN; it is the writer that creates the file and
  /// puts it in WAL mode.
  static Future<ReaderPool> spawn(
    String path, {
    required int count,
    required SqliteOptions options,
  }) async {
    // Started together rather than one after another: each one spawns an
    // isolate, loads the library and opens a connection, and doing that in
    // sequence would multiply the wait before the database is usable.
    final spawning = [
      for (var i = 0; i < count; i++)
        SqliteWorkerHandle.spawn(path, readOnly: true, options: options),
    ];
    final readers = <SqliteWorkerHandle>[];
    Object? failure;
    StackTrace? trace;
    for (final pending in spawning) {
      try {
        readers.add(await pending);
      } on Object catch (error, stackTrace) {
        // Every spawn is still awaited after one of them has failed, so a
        // reader that did come up is closed below rather than left running
        // with nobody holding it.
        failure ??= error;
        trace ??= stackTrace;
      }
    }
    if (failure != null) {
      await Future.wait(readers.map((reader) => reader.close()));
      Error.throwWithStackTrace(failure, trace!);
    }
    return ReaderPool._(readers, options.acquireTimeout);
  }

  final List<SqliteWorkerHandle> _readers;

  /// The free ones, lent from the end: the reader that ran the last
  /// statement runs the next one, and its cache is the warm one.
  ///
  /// The same order concentrates the damage if a reader ever dies, since
  /// nothing here retires one: the dead reader stays the preferred pick, so
  /// every later read fails on it rather than one read in [size]. Left that
  /// way deliberately -- dropping a handle with nothing to replace it and
  /// nowhere to fall back to would turn reads that fail loudly into reads
  /// that wait forever.
  final List<SqliteWorkerHandle> _idle;

  final Queue<Completer<SqliteWorkerHandle>> _waiting = Queue();

  /// How long a read waits here before it is given up on.
  /// [SqliteOptions.acquireTimeout] is where the reason it bounds this wait
  /// and no other one is written down.
  final Duration _acquireTimeout;

  /// Set by [close], and what tells a later [withReader] that waiting for a
  /// reader would mean waiting forever.
  Future<void>? _closing;

  /// How many readers there are. Zero for a database that cannot be reached
  /// from a second connection at all, which is every memory database.
  int get size => _readers.length;

  /// How many of them are running a statement.
  int get busy => _readers.length - _idle.length;

  /// How many reads are waiting for one to come free.
  int get queued => _waiting.length;

  /// Runs [fn] on a free reader, waiting up to [_acquireTimeout] for one
  /// when they are all busy.
  ///
  /// [fn] is called before this returns whenever a reader is free, so by
  /// then the statement is on that isolate's port rather than a microtask
  /// away -- which is what lets [close] wait for a statement the caller had
  /// only just handed over.
  ///
  /// [sql] is carried for the failure alone: a read that never got a reader
  /// has to be able to say which statement it was.
  ///
  /// Not to be called on a pool of no readers: there would be nothing to
  /// wait for, so the wait would never end. A caller asks [size] first and
  /// sends the read to the writer instead.
  Future<T> withReader<T>(
    Future<T> Function(SqliteWorkerHandle reader) fn, {
    required String sql,
  }) {
    // Says so rather than hanging, which is what breaking that precondition
    // would otherwise look like from the outside.
    assert(size > 0, 'a read cannot wait for a reader when there are none');
    if (_closing != null) return Future.error(StateError(_closedMessage));
    if (_idle.isEmpty) return _lendWhenFree(fn, sql);
    return _lend(_idle.removeLast(), fn);
  }

  /// Asks every reader to close its connection and stop, and waits for all
  /// of them to be gone. Safe to call twice.
  ///
  /// Whoever is still queued is failed here rather than left waiting for a
  /// reader that is never coming free.
  Future<void> close() {
    final closing = _closing;
    if (closing != null) return closing;
    final waiting = _waiting.toList();
    _waiting.clear();
    for (final completer in waiting) {
      completer.completeError(StateError(_closedMessage));
    }
    // Each handle waits for the statement its isolate is running, because an
    // FFI call cannot be interrupted.
    return _closing = Future.wait(_readers.map((reader) => reader.close()));
  }

  /// Queues for a reader, and gives up once [_acquireTimeout] has passed.
  ///
  /// The only wait in the driver that is bounded, and the only one worth
  /// bounding: it is the one that gets worse the longer it lasts -- every
  /// reader busy and more reads still arriving -- so a caller left queueing
  /// without end would hear nothing while its latency grew.
  Future<T> _lendWhenFree<T>(
    Future<T> Function(SqliteWorkerHandle reader) fn,
    String sql,
  ) {
    final waiting = Completer<SqliteWorkerHandle>();
    _waiting.add(waiting);
    final giveUp = Timer(_acquireTimeout, () {
      // Out of the queue before the failure goes out, so [_release] cannot
      // hand a reader to a caller that has stopped waiting. Such a reader
      // would run nothing and never come back, leaving the pool to count it
      // busy for the rest of the database's life -- a worse fault than the
      // wait being bounded here, and it would take every later read with it.
      _waiting.remove(waiting);
      waiting.completeError(
        SqliteTimeoutException(timeout: _acquireTimeout, sql: sql),
      );
    });
    // Cancelled however the wait ended, the timeout included. Completing a
    // completer schedules microtasks, and microtasks all run before the
    // event loop reaches a timer, so a reader or a close that gets there
    // first always cancels this in time.
    return waiting.future
        .whenComplete(giveUp.cancel)
        .then((reader) => _lend(reader, fn));
  }

  Future<T> _lend<T>(
    SqliteWorkerHandle reader,
    Future<T> Function(SqliteWorkerHandle reader) fn,
  ) {
    // The invariant that keeps this pool's idea of a busy reader and the
    // reader's own from coming apart, asserted at both ends of a loan
    // because it is the one an honest mistake breaks: bounding the round
    // trip rather than the wait -- send(request).timeout(d) -- would give
    // the reader back here while its statement was still running on the
    // isolate. Future.timeout does not touch the request it wraps, so the
    // handle would still be holding it and nothing over there would notice.
    assert(!reader.busy, 'a reader is lent only with nothing outstanding');
    // Through Future.sync so that [fn] throwing where it stands still gives
    // the reader back: a leaked one would cost the pool a connection for the
    // rest of the database's life.
    return Future.sync(() => fn(reader)).whenComplete(() => _release(reader));
  }

  void _release(SqliteWorkerHandle reader) {
    // The other end of the loan. A response is taken out of the handle's
    // pending map before its caller is completed, so a reader that got here
    // by answering has nothing left outstanding.
    assert(!reader.busy, 'a reader comes back only once nothing is left');
    if (_waiting.isEmpty) {
      _idle.add(reader);
      return;
    }
    // Straight to whoever has waited longest. Putting it back on the idle
    // list first would let a read that arrived later overtake one already
    // queued, for no gain -- the reader is the same either way.
    _waiting.removeFirst().complete(reader);
  }
}
