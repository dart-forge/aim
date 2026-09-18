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

  test('a rollback that fails reports both failures', () async {
    await expectLater(
      db.transaction((tx) async {
        // Ends the transaction behind the driver's back, so the driver's own
        // ROLLBACK has nothing left to roll back.
        await tx.execute('ROLLBACK');
        throw StateError('the original failure');
      }),
      throwsA(
        // The rollback failure is the one that gets thrown, because a
        // connection left inside an open transaction is the worse problem --
        // but it has to say what it was rolling back.
        isA<SqliteException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('no transaction is active'),
            contains('the original failure'),
          ),
        ),
      ),
    );
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

      late Future<int> outside;
      final inside = db.transaction((tx) async {
        await tx.execute('INSERT INTO t VALUES (1)');
        // Queued while the writer is held; must not join this transaction.
        outside = db.execute('INSERT INTO t VALUES (2)');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        throw StateError('roll back');
      });

      await expectLater(inside, throwsA(isA<StateError>()));
      // The rolled back transaction took 1 with it; the queued write survived.
      expect(await outside, 1);
      expect(await db.query('SELECT a FROM t'), [
        {'a': 2},
      ]);
    },
  );

  test('a second transaction waits for the first', () async {
    await db.execute('CREATE TABLE t (a INTEGER)');

    final first = db.transaction((tx) async {
      await tx.execute('INSERT INTO t VALUES (1)');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    // A second BEGIN on a connection already in a transaction is an error,
    // so this only gets through if transactions queue behind each other the
    // way plain statements do.
    final second = db.transaction(
      (tx) => tx.execute('INSERT INTO t VALUES (2)'),
    );

    await first;
    await second;

    expect(await db.query('SELECT a FROM t ORDER BY a'), [
      {'a': 1},
      {'a': 2},
    ]);
  });

  test('a statement on the transaction after it ends is refused', () async {
    late Transaction escaped;
    await db.transaction((tx) async => escaped = tx);

    expect(() => escaped.query('SELECT 1'), throwsA(isA<StateError>()));
  });
}
