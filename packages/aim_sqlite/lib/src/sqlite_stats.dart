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

  /// Value equality, because the question asked of two snapshots is whether
  /// anything moved between them, not whether they are the same object.
  @override
  bool operator ==(Object other) =>
      other is SqliteStats &&
      other.readers == readers &&
      other.busyReaders == busyReaders &&
      other.queued == queued &&
      other.writerBusy == writerBusy;

  @override
  int get hashCode => Object.hash(readers, busyReaders, queued, writerBusy);

  /// Being logged is what this class is for, so it says what it holds
  /// instead of leaving a line reading "Instance of 'SqliteStats'".
  @override
  String toString() =>
      'SqliteStats(readers: $readers, busyReaders: $busyReaders, '
      'queued: $queued, writerBusy: $writerBusy)';
}
