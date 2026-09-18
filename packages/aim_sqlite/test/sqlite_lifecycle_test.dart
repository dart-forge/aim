import 'dart:async';
import 'dart:io';

import 'package:aim_sqlite/aim_sqlite.dart';
import 'package:test/test.dart';

/// Takes a few hundred milliseconds. Every test file that needs a slow
/// statement declares its own copy -- a shared test helper would be one more
/// file to find, and this is three lines.
const heavyQuery = '''
  WITH RECURSIVE counter(x) AS (
    SELECT 1 UNION ALL SELECT x + 1 FROM counter WHERE x < 2000000
  )
  SELECT count(*) AS n FROM counter
''';

void main() {
  late Directory dir;

  // Each test opens its own database: the reader count and the timeout are
  // what is under test here, and two of them close the database themselves.
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('aim_sqlite_test');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('a query that waits too long for an isolate times out', () async {
    final db = await SqliteDatabase.open(
      '${dir.path}/app.db',
      readers: 1,
      acquireTimeout: const Duration(milliseconds: 50),
    );
    addTearDown(db.close);
    // The one reader is busy for a few hundred milliseconds, so the read
    // below waits several times its own timeout however slow the machine is.
    final busy = db.query(heavyQuery);

    await expectLater(
      db.query('SELECT 1'),
      throwsA(
        isA<SqliteTimeoutException>().having(
          (e) => e.timeout,
          'timeout',
          const Duration(milliseconds: 50),
        ),
      ),
    );
    await busy;
  });

  test('a read that gave up waiting leaves the pool whole', () async {
    // The failure mode worth a test of its own: a reader handed to a caller
    // that has stopped waiting runs nothing and is never given back, so the
    // pool would count it busy for the rest of the database's life and every
    // later read would time out too.
    final db = await SqliteDatabase.open(
      '${dir.path}/app.db',
      readers: 1,
      acquireTimeout: const Duration(milliseconds: 50),
    );
    addTearDown(db.close);
    final busy = db.query(heavyQuery);

    await expectLater(
      db.query('SELECT 1'),
      throwsA(isA<SqliteTimeoutException>()),
    );
    expect(db.stats.queued, 0);

    await busy;
    expect(db.stats.busyReaders, 0);
    expect(await db.query('SELECT 1 AS a'), [
      {'a': 1},
    ]);
  });

  test('the timeout is about waiting for an isolate, not for a lock', () async {
    // busyTimeout is SQLite waiting on the file; acquireTimeout is this
    // driver waiting for a worker. A slow statement must not trip
    // acquireTimeout for itself -- it is not waiting for anything.
    final db = await SqliteDatabase.open(
      '${dir.path}/app.db',
      readers: 1,
      acquireTimeout: const Duration(milliseconds: 50),
    );
    addTearDown(db.close);

    expect(await db.query(heavyQuery), hasLength(1));
  });

  test('a call queued behind a transaction is not timed out', () async {
    // The writer's queue is not what acquireTimeout bounds. A transaction
    // holds the writer for as long as its body runs, and the call waiting
    // behind it is waiting for work that is proceeding normally.
    final db = await SqliteDatabase.open(
      '${dir.path}/app.db',
      acquireTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(db.close);
    await db.execute('CREATE TABLE t (a INTEGER)');
    final holding = Completer<void>();
    final letGo = Completer<void>();

    final held = db.transaction((tx) async {
      await tx.execute('INSERT INTO t VALUES (1)');
      holding.complete();
      await letGo.future;
    });
    await holding.future;
    // From outside the body, so it queues rather than being refused.
    final queued = db.execute('INSERT INTO t VALUES (2)');
    // Ten times acquireTimeout with the writer held throughout: a bound on
    // this wait would have fired long before the release.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    letGo.complete();
    await held;

    expect(await queued, 1);
  });

  test('close lets the statement in flight finish', () async {
    final db = await SqliteDatabase.open('${dir.path}/app.db', readers: 1);
    await db.execute('CREATE TABLE t (a INTEGER)');

    final inFlight = db.execute('INSERT INTO t VALUES (1)');
    await db.close();

    expect(await inFlight, 1);
    // Reopened, so this is the committed database rather than the driver's
    // own account of what it did.
    final reopened = await SqliteDatabase.open('${dir.path}/app.db');
    addTearDown(reopened.close);
    expect(await reopened.query('SELECT count(*) AS n FROM t'), [
      {'n': 1},
    ]);
  });

  test('close refuses what was still queued', () async {
    final db = await SqliteDatabase.open('${dir.path}/app.db', readers: 1);

    final running = db.query(heavyQuery);
    // Waited on before the close rather than after it: the queue is failed
    // from inside close(), and a future nobody is listening to yet reports
    // that as an unhandled error instead of to this test.
    final refused = expectLater(
      db.query('SELECT 1'),
      throwsA(isA<StateError>()),
    );
    await db.close();

    await running;
    await refused;
  });

  test('a statement after close is refused', () async {
    final db = await SqliteDatabase.open('${dir.path}/app.db');
    await db.close();

    expect(() => db.query('SELECT 1'), throwsA(isA<StateError>()));
  });

  test('close twice is fine', () async {
    final db = await SqliteDatabase.open('${dir.path}/app.db');

    await db.close();
    await expectLater(db.close(), completes);
  });

  test('stats report what the isolates are doing', () async {
    final db = await SqliteDatabase.open('${dir.path}/app.db', readers: 2);
    addTearDown(db.close);

    expect(db.stats.readers, 2);
    expect(db.stats.busyReaders, 0);
    expect(db.stats.writerBusy, isFalse);

    // Lent out before query() returns, so this needs no delay to settle.
    final running = db.query(heavyQuery);
    expect(db.stats.busyReaders, 1);

    await running;
    expect(db.stats.busyReaders, 0);
  });
}
