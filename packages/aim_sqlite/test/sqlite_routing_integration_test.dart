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

  // Each test opens its own database, because the reader count is what is
  // under test here.
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('aim_sqlite_test');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test(
    'a read-only connection can read a WAL database the writer owns',
    () async {
      final db = await SqliteDatabase.open('${dir.path}/app.db', readers: 2);
      addTearDown(db.close);
      await db.execute('CREATE TABLE t (a INTEGER)');
      await db.execute('INSERT INTO t VALUES (1)');

      // Goes to a reader, which was opened with SQLITE_OPEN_READONLY. The
      // whole design rests on this: a misrouted write is then refused by the C
      // library rather than only by the driver's own check.
      expect(await db.query('SELECT a FROM t'), [
        {'a': 1},
      ]);
    },
  );

  test(
    'a write sent through query() lands on the writer, not a reader',
    () async {
      final db = await SqliteDatabase.open('${dir.path}/app.db', readers: 2);
      addTearDown(db.close);
      await db.execute('CREATE TABLE t (a INTEGER)');

      // INSERT goes to the writer on its leading keyword alone, so this
      // exercises the first stage only -- no reader is involved and
      // stmt_readonly never runs. The test below is the one that reaches the
      // second stage.
      final rows = await db.query('INSERT INTO t VALUES (1) RETURNING a');

      expect(rows, [
        {'a': 1},
      ]);
      expect(await db.query('SELECT count(*) AS n FROM t'), [
        {'n': 1},
      ]);
    },
  );

  test('a brand new database can be read through a reader', () async {
    // Names the WAL index step. Without it the readers cannot open a database
    // nothing has written yet, and three other tests in this file fail with a
    // confusing SQLITE_CANTOPEN instead of this one failing with its name.
    final db = await SqliteDatabase.open('${dir.path}/fresh.db', readers: 2);
    addTearDown(db.close);

    expect(await db.query('SELECT 1 AS a'), [
      {'a': 1},
    ]);
  });

  test(
    'a write that looks like a read is caught by the second stage',
    () async {
      final db = await SqliteDatabase.open('${dir.path}/app.db', readers: 2);
      addTearDown(db.close);
      await db.execute('CREATE TABLE t (a INTEGER)');

      // Leading keyword WITH, so the first stage sends this to a reader. Only
      // sqlite3_stmt_readonly can tell that it writes, and the reader must hand
      // it back rather than stepping it -- the read-only connection would
      // otherwise refuse it with a bare "attempt to write a readonly database".
      // Named parameters, so the redirect re-encodes those too.
      final rows = await db.query(
        'WITH v(x) AS (VALUES (:a)) INSERT INTO t SELECT x FROM v RETURNING a',
        params: {'a': 7},
      );

      expect(rows, [
        {'a': 7},
      ]);
      expect(await db.query('SELECT count(*) AS n FROM t'), [
        {'n': 1},
      ]);
    },
  );

  test('a read batch with a write in it runs nothing on the reader', () async {
    final db = await SqliteDatabase.open('${dir.path}/app.db', readers: 2);
    addTearDown(db.close);
    await db.execute('CREATE TABLE t (a INTEGER)');

    // The leading SELECT routes this to a reader. The reader must prepare both
    // statements and hand the batch back before stepping the SELECT.
    await db.query('SELECT 1; INSERT INTO t VALUES (1)');

    expect(await db.query('SELECT count(*) AS n FROM t'), [
      {'n': 1},
    ]);
  });

  test(
    'a read batch that cannot be prepared whole fails on the reader',
    () async {
      final db = await SqliteDatabase.open('${dir.path}/app.db', readers: 2);
      addTearDown(db.close);

      // The known cost of checking the whole batch before stepping any of it:
      // the reader prepares every statement up front, so one that depends on
      // an earlier statement having run cannot be prepared at all. Preparing
      // them one at a time instead would mean stepping a statement before
      // knowing whether the batch writes, which is the property being bought.
      await expectLater(
        db.query('SELECT 1; CREATE TEMP TABLE t AS SELECT 1; SELECT * FROM t'),
        throwsA(
          isA<SqliteException>().having(
            (e) => e.message,
            'message',
            contains('no such table'),
          ),
        ),
      );
    },
  );

  test('reads run while a transaction holds the writer', () async {
    final db = await SqliteDatabase.open('${dir.path}/app.db', readers: 2);
    addTearDown(db.close);
    await db.execute('CREATE TABLE t (a INTEGER)');
    await db.execute('INSERT INTO t VALUES (1)');

    // Issued from outside the body, because a call on the database from
    // inside it is refused: it would wait for its own transaction. The
    // completers hold the writer while the read below goes through.
    final bodyRunning = Completer<void>();
    final letGo = Completer<void>();
    final holding = db.transaction((tx) async {
      await tx.execute('INSERT INTO t VALUES (2)');
      bodyRunning.complete();
      await letGo.future;
    });
    await bodyRunning.future;

    // WAL: the reader sees the snapshot from before the transaction and does
    // not wait for it. A 2 would mean the read had joined the transaction;
    // a timeout, that it had queued behind it.
    expect(
      await db
          .query('SELECT count(*) AS n FROM t')
          .timeout(const Duration(seconds: 2)),
      [
        {'n': 1},
      ],
    );

    letGo.complete();
    await holding;
    // And the snapshot is per statement, so the commit is visible at once.
    expect(await db.query('SELECT count(*) AS n FROM t'), [
      {'n': 2},
    ]);
  });

  test('execute() goes to the writer even when the SQL only reads', () async {
    final db = await SqliteDatabase.open('${dir.path}/app.db', readers: 2);
    addTearDown(db.close);
    final order = <String>[];
    final bodyRunning = Completer<void>();
    final letGo = Completer<void>();
    final holding = db.transaction((tx) async {
      bodyRunning.complete();
      await letGo.future;
      order.add('transaction');
    });
    await bodyRunning.future;

    // query() routes a SELECT to a reader, which answers while the writer is
    // held. execute() never consults the routing, so the same SQL waits for
    // the writer instead -- which is what puts it last.
    //
    // The read is given a timeout because the regression here is that it
    // queues for the writer too: without one it would wait for a lease the
    // line below releases, and the test would hang to its own timeout
    // instead of saying what went wrong.
    final reading = db
        .query('SELECT 1 AS a')
        .timeout(const Duration(seconds: 2))
        .then((_) => order.add('query'));
    final executing = db
        .execute('SELECT 1 AS a')
        .then((_) => order.add('execute'));
    try {
      await reading;
    } finally {
      // Even on that failure, so the transaction ends and the teardown does
      // not close a database whose writer is still held.
      letGo.complete();
    }
    await Future.wait([holding, executing]);

    expect(order, ['query', 'transaction', 'execute']);
  });

  test('reads run in parallel across readers', () async {
    // This measures parallelism, which cannot happen on one core. Asserted so
    // a constrained machine fails with the reason rather than with a ratio.
    expect(
      Platform.numberOfProcessors,
      greaterThanOrEqualTo(2),
      reason: 'this test needs at least two cores to mean anything',
    );

    final db = await SqliteDatabase.open('${dir.path}/app.db', readers: 2);
    addTearDown(db.close);
    // Warm up so the measurement is not dominated by isolate start up.
    await db.query(heavyQuery);

    final one = Stopwatch()..start();
    await db.query(heavyQuery);
    one.stop();

    final two = Stopwatch()..start();
    await Future.wait([db.query(heavyQuery), db.query(heavyQuery)]);
    two.stop();

    // Two in parallel on two readers take far less than twice one.
    expect(
      two.elapsedMicroseconds,
      lessThan(one.elapsedMicroseconds * 18 ~/ 10),
    );
  });

  test('a third read waits for one of the two readers', () async {
    final db = await SqliteDatabase.open('${dir.path}/app.db', readers: 2);
    addTearDown(db.close);

    final reads = [for (var i = 0; i < 3; i++) db.query(heavyQuery)];

    // Lent out before query() returns, so this needs no delay to settle.
    expect(db.stats.readers, 2);
    expect(db.stats.busyReaders, 2);
    expect(db.stats.queued, 1);

    await Future.wait(reads);
    expect(db.stats.busyReaders, 0);
    expect(db.stats.queued, 0);
  });

  test('the writer counts as busy while it runs a statement', () async {
    final db = await SqliteDatabase.open('${dir.path}/app.db', readers: 2);
    addTearDown(db.close);

    // Sent before execute() returns, so this needs no delay to settle.
    final writing = db.execute('CREATE TABLE t (a INTEGER)');
    expect(db.stats.writerBusy, isTrue);

    await writing;
    expect(db.stats.writerBusy, isFalse);
  });

  test('a memory database keeps everything on the one connection', () async {
    final db = await SqliteDatabase.open(':memory:', readers: 4);
    addTearDown(db.close);
    await db.execute('CREATE TABLE t (a INTEGER)');
    await db.execute('INSERT INTO t VALUES (1)');

    // A reader would have opened its own empty database.
    expect(await db.query('SELECT a FROM t'), [
      {'a': 1},
    ]);
    expect(db.stats.readers, 0);
  });

  test(
    'the URI spellings of a memory database get no readers either',
    () async {
      for (final path in const ['file::memory:', 'file:app.db?mode=memory']) {
        final db = await SqliteDatabase.open(path, readers: 4);
        addTearDown(db.close);
        await db.execute('CREATE TABLE t (a INTEGER)');
        await db.execute('INSERT INTO t VALUES (1)');

        expect(await db.query('SELECT a FROM t'), [
          {'a': 1},
        ], reason: path);
        expect(db.stats.readers, 0, reason: path);
      }
    },
  );

  test(
    'a file whose query merely mentions memory still gets readers',
    () async {
      // "mode" has to be read as a parameter of its own: as a substring,
      // "mode=memory" is in here too, and this is an ordinary file.
      final db = await SqliteDatabase.open(
        'file:${dir.path}/app.db?other_mode=memory_foo',
        readers: 2,
      );
      addTearDown(db.close);
      await db.execute('CREATE TABLE t (a INTEGER)');
      await db.execute('INSERT INTO t VALUES (1)');

      expect(db.stats.readers, 2);
      expect(await db.query('SELECT a FROM t'), [
        {'a': 1},
      ]);
    },
  );
}
