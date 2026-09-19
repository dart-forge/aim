/// How hard SQLite works to get a commit onto the disk.
enum SqliteSynchronous {
  /// Faster, and loses the most recent commits when the machine loses power.
  /// In WAL mode a crash of the process alone is still safe.
  normal('NORMAL'),

  /// Survives a power loss.
  full('FULL');

  const SqliteSynchronous(this.pragmaValue);

  /// The value written to `PRAGMA synchronous`.
  final String pragmaValue;
}

/// Tuning knobs for a SQLite database.
class SqliteOptions {
  SqliteOptions({
    this.readers = 4,
    this.busyTimeout = const Duration(seconds: 5),
    this.synchronous = SqliteSynchronous.full,
    this.libraryPath,
    this.acquireTimeout = const Duration(seconds: 30),
  }) {
    if (readers < 0) {
      throw ArgumentError.value(readers, 'readers', 'must not be negative');
    }
    _requireNonNegative(busyTimeout, 'busyTimeout');
    _requireNonNegative(acquireTimeout, 'acquireTimeout');
  }

  /// Read-only connections, each on its own isolate. Reads are spread over
  /// them while writes always go to the single writer. Zero sends everything
  /// to the writer, which is all a memory database can do.
  final int readers;

  /// How long SQLite waits for a lock another connection holds before
  /// giving up with SQLITE_BUSY. [Duration.zero] gives up immediately.
  ///
  /// This is SQLite waiting on the database file. [acquireTimeout] is this
  /// driver waiting for a connection to run on, which is a different wait
  /// and does not overlap with it.
  final Duration busyTimeout;

  /// `PRAGMA synchronous`, applied to the writer.
  final SqliteSynchronous synchronous;

  /// Where to load libsqlite3 from. Null looks at the AIM_SQLITE_LIBRARY
  /// environment variable and then the platform defaults.
  final String? libraryPath;

  /// How long a read waits for one of the [readers] to come free before it
  /// is failed with a SqliteTimeoutException. [Duration.zero] refuses a
  /// read that finds them all busy instead of waiting at all.
  ///
  /// This is the driver waiting for a connection to run on, not SQLite
  /// waiting for a lock -- that is [busyTimeout]. A read costs at worst the
  /// two of them plus however long the statement itself takes.
  ///
  /// It bounds that wait and nothing else.
  ///
  /// Not the running time. An FFI call cannot be interrupted, so a limit
  /// there could only be a limit on when the driver stops reporting the
  /// result -- the statement would run to the end regardless, and the
  /// connection would stay busy while the caller was told otherwise.
  ///
  /// Not the writer's queue either. There is one writer, and writes,
  /// transactions and reads with nowhere else to go pass through it in
  /// order; a transaction holds it for as long as its body runs. A call
  /// waiting there is waiting for work that is proceeding normally, so
  /// failing it would turn one slow transaction into errors on calls that
  /// did nothing wrong. What is bounded is the wait with no such owner:
  /// every reader busy, more reads still arriving, and nothing about it
  /// improving on its own.
  final Duration acquireTimeout;

  static void _requireNonNegative(Duration d, String name) {
    if (d.isNegative) {
      throw ArgumentError.value(d, name, 'must not be negative');
    }
  }
}
