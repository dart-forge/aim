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
  final Duration busyTimeout;

  /// `PRAGMA synchronous`, applied to the writer.
  final SqliteSynchronous synchronous;

  /// Where to load libsqlite3 from. Null looks at the AIM_SQLITE_LIBRARY
  /// environment variable and then the platform defaults.
  final String? libraryPath;

  /// How long a statement waits for a free connection.
  final Duration acquireTimeout;

  static void _requireNonNegative(Duration d, String name) {
    if (d.isNegative) {
      throw ArgumentError.value(d, name, 'must not be negative');
    }
  }
}
