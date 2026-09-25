import 'package:aim_mysql/src/statement.dart';
import 'package:aim_mysql/src/types/column_type.dart';
import 'package:test/test.dart';

void main() {
  var nextId = 1;
  var prepared = <String>[];
  var closed = <int>[];

  StatementCache cacheOf({int capacity = 64}) => StatementCache(
    capacity: capacity,
    prepare: (sql) async {
      prepared.add(sql);
      return PreparedStatement(
        id: nextId++,
        parameterCount: 0,
        columns: const <ColumnDefinition>[],
      );
    },
    close: (id) async => closed.add(id),
  );

  setUp(() {
    nextId = 1;
    prepared = [];
    closed = [];
  });

  test('prepares once and reuses', () async {
    final cache = cacheOf();

    final first = await cache.get('SELECT 1');
    final second = await cache.get('SELECT 1');

    expect(prepared, ['SELECT 1']);
    expect(second.id, first.id);
  });

  test('different SQL gets its own statement', () async {
    final cache = cacheOf();

    await cache.get('SELECT 1');
    await cache.get('SELECT 2');

    expect(prepared, ['SELECT 1', 'SELECT 2']);
    expect(cache.size, 2);
  });

  test('two callers asking at once prepare once, not twice', () async {
    // Without this, a pool releasing several waiters at the same moment
    // prepares the same statement repeatedly and leaks all but the last.
    final cache = cacheOf();

    final results = await Future.wait([
      cache.get('SELECT 1'),
      cache.get('SELECT 1'),
    ]);

    expect(prepared, ['SELECT 1']);
    expect(results[0].id, results[1].id);
  });

  test('evicts the least recently used and closes it on the server', () async {
    // Leaving it open would hold server-side memory for a statement nothing
    // can reach any more.
    final cache = cacheOf(capacity: 2);

    final a = await cache.get('A');
    await cache.get('B');
    await cache.get('A'); // A is now the most recent
    await cache.get('C'); // so B goes

    expect(closed, hasLength(1));
    expect(cache.size, 2);
    expect((await cache.get('A')).id, a.id, reason: 'A was kept');
    await cache.get('B'); // B was evicted above, so this re-prepares it
    expect(prepared, ['A', 'B', 'C', 'B'], reason: 'B had to be redone');
  });

  test(
    'eviction defers closing a statement a caller has marked in use',
    () async {
      // Without this, a concurrent caller that already resolved the
      // statement from the cache -- and is about to send
      // COM_STMT_EXECUTE for it -- can have eviction close the very id
      // it is about to execute, out from under it.
      final cache = cacheOf(capacity: 2);

      final b = await cache.get('B');
      cache.markInUse(b);

      await cache.get('A');
      await cache.get('C'); // would evict B, but B is checked out

      expect(
        closed,
        isEmpty,
        reason: 'B is still in use; closing it now would race the execute',
      );

      cache.markDone(b);

      expect(closed, [b.id], reason: 'released, so the deferred close runs');
    },
  );

  test('markInUse/markDone are reference-counted across two concurrent '
      'checkouts of the same statement', () async {
    final cache = cacheOf(capacity: 2);

    final b = await cache.get('B');
    cache.markInUse(b);
    cache.markInUse(b); // a second caller holding the same statement

    await cache.get('A');
    await cache.get('C'); // would evict B

    cache.markDone(b); // first caller finishes; second still holds it
    expect(closed, isEmpty, reason: 'the second checkout still holds it');

    cache.markDone(b); // second caller finishes
    expect(closed, [b.id]);
  });

  test('invalidate drops one entry so the next get re-prepares', () async {
    // Which is what happens after the server says the statement needs
    // re-preparing.
    final cache = cacheOf();

    final first = await cache.get('SELECT 1');
    cache.invalidate('SELECT 1');
    final second = await cache.get('SELECT 1');

    expect(prepared, ['SELECT 1', 'SELECT 1']);
    expect(second.id, isNot(first.id));
  });

  test('invalidate does not close the statement on the server', () async {
    // The statement the server is complaining about is already gone as far
    // as it is concerned; closing an id it has dropped is an error.
    final cache = cacheOf();

    await cache.get('SELECT 1');
    cache.invalidate('SELECT 1');

    expect(closed, isEmpty);
  });

  test('invalidating something absent is not an error', () {
    expect(() => cacheOf().invalidate('SELECT 1'), returnsNormally);
  });

  test('clear closes everything it was holding', () async {
    final cache = cacheOf();

    await cache.get('A');
    await cache.get('B');
    await cache.clear();

    expect(closed, hasLength(2));
    expect(cache.size, 0);
  });

  test('a failed prepare is not cached', () async {
    // Otherwise a transient failure poisons the entry for the life of the
    // connection.
    var fail = true;
    final cache = StatementCache(
      capacity: 4,
      prepare: (sql) async {
        if (fail) throw StateError('no');
        return PreparedStatement(
          id: 1,
          parameterCount: 0,
          columns: const <ColumnDefinition>[],
        );
      },
      close: (id) async {},
    );

    await expectLater(cache.get('A'), throwsA(isA<StateError>()));
    expect(cache.size, 0);

    fail = false;
    expect((await cache.get('A')).id, 1);
  });
}
