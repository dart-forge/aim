/// What a database's connections are doing.
///
/// A snapshot, read where it is asked for: none of it is still guaranteed to
/// hold once the event loop turns again.
class SqliteStats {
  const SqliteStats({
    required this.readers,
    required this.busyReaders,
    required this.queued,
    required this.writerBusy,
  });

  /// How many read-only connections there are. Zero for a memory database,
  /// which no second connection can reach.
  final int readers;

  /// How many of those are running a statement.
  final int busyReaders;

  /// How many reads are waiting for a reader to come free. Writes are not
  /// counted here: they queue for the one writer instead.
  final int queued;

  /// True while the writer is running a statement.
  final bool writerBusy;
}
