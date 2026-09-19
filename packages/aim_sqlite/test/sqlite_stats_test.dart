import 'package:aim_sqlite/aim_sqlite.dart';
import 'package:test/test.dart';

/// A snapshot built from arguments rather than written as a const.
///
/// Deliberately not const: two identical const SqliteStats are canonicalized
/// to one instance, so a test comparing those would pass on identity alone
/// and say nothing about whether this class has value equality at all.
SqliteStats stats({
  int readers = 4,
  int busyReaders = 2,
  int queued = 1,
  bool writerBusy = true,
}) => SqliteStats(
  readers: readers,
  busyReaders: busyReaders,
  queued: queued,
  writerBusy: writerBusy,
);

void main() {
  test('two snapshots of the same numbers are the same value', () {
    // A snapshot is what a caller watching the pool holds on to, so the
    // question it asks of two of them is whether anything changed.
    expect(stats(), stats());
    expect(stats().hashCode, stats().hashCode);
    expect(identical(stats(), stats()), isFalse);
  });

  test('a snapshot differing in any one field is a different value', () {
    expect(stats(readers: 5), isNot(stats()));
    expect(stats(busyReaders: 3), isNot(stats()));
    expect(stats(queued: 0), isNot(stats()));
    expect(stats(writerBusy: false), isNot(stats()));
  });

  test('toString carries every field, since being logged is the point', () {
    expect(
      stats().toString(),
      'SqliteStats(readers: 4, busyReaders: 2, queued: 1, writerBusy: true)',
    );
  });
}
