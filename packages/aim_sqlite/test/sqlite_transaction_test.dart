import 'dart:async';
import 'dart:io';

import 'package:aim_database/aim_database.dart';
import 'package:aim_sqlite/aim_sqlite.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late SqliteDatabase db;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('aim_sqlite_test');
    db = await SqliteDatabase.open('${dir.path}/app.db');
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('commits when the body returns', () async {
    await db.execute('CREATE TABLE t (a INTEGER)');

    await db.transaction((tx) async {
      await tx.execute('INSERT INTO t VALUES (1)');
      await tx.execute('INSERT INTO t VALUES (2)');
    });

    expect(await db.query('SELECT count(*) AS n FROM t'), [
      {'n': 2},
    ]);
  });

  test('rolls back when the body throws, and rethrows', () async {
    await db.execute('CREATE TABLE t (a INTEGER)');

    await expectLater(
      db.transaction((tx) async {
        await tx.execute('INSERT INTO t VALUES (1)');
        throw StateError('no');
      }),
      throwsA(isA<StateError>()),
    );

    expect(await db.query('SELECT count(*) AS n FROM t'), [
      {'n': 0},
    ]);
  });

  test('rolls back when a statement inside it fails', () async {
    await db.execute('CREATE TABLE t (a INTEGER PRIMARY KEY)');

    await expectLater(
      db.transaction((tx) async {
        await tx.execute('INSERT INTO t VALUES (1)');
        await tx.execute('INSERT INTO t VALUES (1)');
      }),
      throwsA(isA<SqliteException>()),
    );

    expect(await db.query('SELECT count(*) AS n FROM t'), [
      {'n': 0},
    ]);
  });

  test('returns what the body returns', () async {
    expect(await db.transaction((tx) async => 42), 42);
  });

  test('reads inside a transaction see its own uncommitted writes', () async {
    await db.execute('CREATE TABLE t (a INTEGER)');

    await db.transaction((tx) async {
      await tx.execute('INSERT INTO t VALUES (1)');

      // Would be 0 if tx.query() went to a reader connection.
      expect(await tx.query('SELECT count(*) AS n FROM t'), [
        {'n': 1},
      ]);
    });
  });

  test(
    'a write waiting on the transaction runs after it, not inside it',
    () async {
      await db.execute('CREATE TABLE t (a INTEGER)');

      // The queued write is issued from OUTSIDE the body, because a call on
      // the database from inside it is refused (it would deadlock). A
      // completer lets this one arrive while the lease is still held, which
      // is the situation under test.
      final bodyRunning = Completer<void>();
      final letGo = Completer<void>();
      final inside = db.transaction((tx) async {
        await tx.execute('INSERT INTO t VALUES (1)');
        bodyRunning.complete();
        await letGo.future;
        throw StateError('roll back');
      });

      await bodyRunning.future;
      // Queued while the writer is held; must not join this transaction.
      final outside = db.execute('INSERT INTO t VALUES (2)');
      letGo.complete();

      await expectLater(inside, throwsA(isA<StateError>()));
      // Awaiting the queued write is what makes this deterministic -- a
      // trailing delay would pass or fail on timing. It also pins that the
      // queued write succeeded rather than being lost with the rollback.
      expect(await outside, 1);
      // The rolled back transaction took 1 with it; the queued write
      // survived.
      expect(await db.query('SELECT a FROM t'), [
        {'a': 2},
      ]);
    },
  );

  test(
    'a rollback with nothing left to roll back reports the original failure',
    () async {
      // SQLite refuses ROLLBACK with "no transaction is active" whenever
      // nothing is open, and that is the ordinary aftermath of a COMMIT it
      // abandoned on a full disk. Reporting it would put SQLITE_ERROR in
      // front of the failure that mattered, which is the whole point of
      // carrying an extended result code at all. Closing the transaction
      // from inside the body reaches that state on demand.
      await db.execute('CREATE TABLE t (a INTEGER)');

      await expectLater(
        db.transaction((tx) async {
          await tx.execute('ROLLBACK');
          throw StateError('the failure that mattered');
        }),
        // Untouched, not wrapped: the benign refusal leaves no trace.
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'the failure that mattered',
          ),
        ),
      );
    },
  );

  test(
    'a failing rollback reports itself and why it was rolling back',
    () async {
      // The rule below has no test unless one forces the rollback to fail.
      // Closing the database under the transaction does it: the ROLLBACK
      // then has no worker to run on.
      await db.execute('CREATE TABLE t (a INTEGER)');

      await expectLater(
        db.transaction((tx) async {
          await tx.execute('INSERT INTO t VALUES (1)');
          await db.close();
          throw StateError('original failure');
        }),
        throwsA(
          predicate(
            (e) => '$e'.contains('original failure'),
            'carries the original failure inside the rollback failure',
          ),
        ),
      );
    },
  );

  test('a second transaction waits for the first', () async {
    await db.execute('CREATE TABLE t (a INTEGER)');
    final order = <String>[];

    final first = db.transaction((tx) async {
      order.add('first begin');
      await tx.execute('INSERT INTO t VALUES (1)');
      order.add('first end');
    });
    final second = db.transaction((tx) async {
      order.add('second begin');
      await tx.execute('INSERT INTO t VALUES (2)');
      order.add('second end');
    });
    await Future.wait([first, second]);

    // Not interleaved: BEGIN IMMEDIATE would fail with SQLITE_BUSY if the
    // second one started while the first held the write lock.
    expect(order, ['first begin', 'first end', 'second begin', 'second end']);
  });

  test(
    'a call on the database from inside the body is refused, not queued',
    () async {
      // Awaiting either of these would wait on the lease the body itself
      // holds, which never comes free. A StateError naming tx beats a
      // permanent hang.
      await db.transaction((tx) async {
        await expectLater(
          db.execute('INSERT INTO t VALUES (1)'),
          throwsA(isA<StateError>()),
        );
        await expectLater(db.query('SELECT 1'), throwsA(isA<StateError>()));
        await expectLater(
          db.transaction((inner) async {}),
          throwsA(isA<StateError>()),
        );
      });
    },
  );

  test(
    'a call on another database from inside the body goes through',
    () async {
      // The refusal is about waiting for the lease this body is holding.
      // Another database has its own writer and its own queue, so nothing
      // there can be waiting on this one; refusing it would be a false alarm
      // with no way around it.
      final other = await SqliteDatabase.open('${dir.path}/other.db');
      addTearDown(other.close);
      await other.execute('CREATE TABLE t (a INTEGER)');

      await db.transaction((tx) async {
        expect(await other.execute('INSERT INTO t VALUES (1)'), 1);
      });

      expect(await other.query('SELECT a FROM t'), [
        {'a': 1},
      ]);
    },
  );

  test(
    'a call the body scheduled runs after the transaction, not refused',
    () async {
      // A zone value travels with everything the body ever scheduled, not
      // only with its synchronous extent, so a timer set up inside the body
      // still finds the marker when it fires. By then the transaction is
      // over and the writer is idle, so refusing the call would leave it
      // waiting for nothing, with no way around it.
      await db.execute('CREATE TABLE t (a INTEGER)');

      final scheduled = Completer<int>();
      await db.transaction((tx) async {
        await tx.execute('INSERT INTO t VALUES (1)');
        Timer.run(() {
          // Forwards the refusal as well as the result, so a StateError
          // here surfaces below rather than going unhandled.
          scheduled.complete(db.execute('INSERT INTO t VALUES (2)'));
        });
      });

      expect(await scheduled.future, 1);
      expect(await db.query('SELECT a FROM t ORDER BY a'), [
        {'a': 1},
        {'a': 2},
      ]);
    },
  );

  test('a concurrent transaction from outside the body still queues', () async {
    // The refusal above must be scoped to the body, not to "a transaction is
    // open" -- another request handler running concurrently is the normal
    // case, and the queue exists for it.
    await db.execute('CREATE TABLE t (a INTEGER)');
    final bodyRunning = Completer<void>();
    final letGo = Completer<void>();

    final first = db.transaction((tx) async {
      await tx.execute('INSERT INTO t VALUES (1)');
      bodyRunning.complete();
      await letGo.future;
    });
    await bodyRunning.future;
    final second = db.transaction((tx) async {
      await tx.execute('INSERT INTO t VALUES (2)');
    });
    letGo.complete();
    await Future.wait([first, second]);

    expect(await db.query('SELECT a FROM t ORDER BY a'), [
      {'a': 1},
      {'a': 2},
    ]);
  });

  test(
    'BEGIN takes the write lock up front, so it fails before the body',
    () async {
      // Nothing else pins IMMEDIATE: with DEFERRED the whole suite stays
      // green. A second connection on the same file is what shows the
      // difference -- DEFERRED would start fine and fail later, on the
      // first write.
      final other = await SqliteDatabase.open(
        '${dir.path}/app.db',
        busyTimeout: Duration.zero,
      );
      addTearDown(other.close);
      final bodyRunning = Completer<void>();
      final letGo = Completer<void>();

      final holding = db.transaction((tx) async {
        await tx.execute('CREATE TABLE t (a INTEGER)');
        bodyRunning.complete();
        await letGo.future;
      });
      await bodyRunning.future;

      var bodyRan = false;
      await expectLater(
        other.transaction((tx) async => bodyRan = true),
        throwsA(isA<SqliteException>()),
      );
      expect(bodyRan, isFalse);

      letGo.complete();
      await holding;
    },
  );

  test('a statement on the transaction after it ends is refused', () async {
    late Transaction escaped;
    await db.transaction((tx) async => escaped = tx);

    expect(() => escaped.query('SELECT 1'), throwsA(isA<StateError>()));
  });
}
