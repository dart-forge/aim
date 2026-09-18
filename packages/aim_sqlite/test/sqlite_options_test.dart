import 'package:aim_sqlite/aim_sqlite.dart';
import 'package:test/test.dart';

void main() {
  test('defaults are the safe ones', () {
    final options = SqliteOptions();

    expect(options.readers, 4);
    expect(options.busyTimeout, const Duration(seconds: 5));
    // NORMAL is faster but loses the most recent commits on power loss.
    expect(options.synchronous, SqliteSynchronous.full);
    expect(options.acquireTimeout, const Duration(seconds: 30));
    expect(options.libraryPath, isNull);
  });

  test('rejects a negative reader count', () {
    expect(() => SqliteOptions(readers: -1), throwsA(isA<ArgumentError>()));
  });

  test('allows zero readers, which is what a memory database gets', () {
    expect(SqliteOptions(readers: 0).readers, 0);
  });

  test('rejects negative durations', () {
    expect(
      () => SqliteOptions(busyTimeout: const Duration(seconds: -1)),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => SqliteOptions(acquireTimeout: const Duration(seconds: -1)),
      throwsA(isA<ArgumentError>()),
    );
  });
}
