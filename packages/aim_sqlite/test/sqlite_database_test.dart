import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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
  late SqliteDatabase db;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('aim_sqlite_test');
    db = await SqliteDatabase.open('${dir.path}/app.db');
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('open throws what the worker could not open', () {
    // The worker sends the failure in place of its port, so this surfaces
    // here rather than as an isolate that never answers.
    expect(
      SqliteDatabase.open('${dir.path}/no-such-directory/app.db'),
      throwsA(
        isA<SqliteException>().having((e) => e.sql, 'sql', contains('open')),
      ),
    );
  });

  test('puts the database in WAL mode', () async {
    final rows = await db.query('PRAGMA journal_mode');

    expect(rows.single.values.single, 'wal');
  });

  test('turns foreign keys on, which SQLite leaves off', () async {
    final rows = await db.query('PRAGMA foreign_keys');

    expect(rows.single.values.single, 1);
  });

  test('reports the rows a statement changed', () async {
    await db.execute('CREATE TABLE t (a INTEGER)');

    expect(await db.execute('INSERT INTO t VALUES (1), (2)'), 2);
    expect(await db.execute('UPDATE t SET a = 3'), 2);
    expect(await db.execute('DELETE FROM t WHERE a = 3'), 2);
  });

  test('reports zero for a statement that changes nothing', () async {
    expect(await db.execute('CREATE TABLE t (a INTEGER)'), 0);
  });

  test('a statement that reports no count does not inherit the last', () async {
    // sqlite3_changes keeps whatever the last statement that reported a
    // count left in it, so a DDL statement run after an INSERT would
    // otherwise claim the rows the INSERT changed.
    await db.execute('CREATE TABLE t (a INTEGER)');
    await db.execute('INSERT INTO t VALUES (1), (2)');

    expect(await db.execute('CREATE TABLE u (a INTEGER)'), 0);
  });

  test('sums the counts when one call runs several statements', () async {
    await db.execute('CREATE TABLE t (a INTEGER)');

    expect(
      await db.execute('INSERT INTO t VALUES (1); INSERT INTO t VALUES (2)'),
      2,
    );
  });

  test('returns the rows of the last statement that produced any', () async {
    await db.execute('CREATE TABLE t (a INTEGER)');
    await db.execute('INSERT INTO t VALUES (1)');

    final rows = await db.query('SELECT 99 AS x; SELECT a FROM t');

    expect(rows, [
      {'a': 1},
    ]);
  });

  test('steps over a trailing comment and a bare semicolon', () async {
    // prepare_v2 answers with no statement at all for text it cannot run,
    // and the batch has to walk past that rather than stall on it.
    await db.execute('CREATE TABLE t (a INTEGER);');

    expect(
      await db.execute('INSERT INTO t VALUES (1); -- nothing after this\n'),
      1,
    );
    expect(await db.query('SELECT a FROM t; '), [
      {'a': 1},
    ]);
  });

  test('keys rows by column name', () async {
    final rows = await db.query('SELECT 1 AS a, 2 AS b');

    expect(rows.single, {'a': 1, 'b': 2});
  });

  test('binds positional parameters', () async {
    final rows = await db.query('SELECT ? AS a, ? AS b', args: [1, 'two']);

    expect(rows.single, {'a': 1, 'b': 'two'});
  });

  test('binds named parameters', () async {
    final rows = await db.query(
      'SELECT :a AS a, :b AS b',
      params: {'a': 1, 'b': 'two'},
    );

    expect(rows.single, {'a': 1, 'b': 'two'});
  });

  test('refuses a named parameter the statement does not have', () async {
    expect(
      () => db.query('SELECT :a', params: {'nope': 1}),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('refuses the wrong number of positional parameters', () async {
    expect(
      () => db.query('SELECT ?, ?', args: [1]),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('refuses parameters on any statement but the first', () async {
    // Only the first statement of a batch is bound, and leaving a later
    // placeholder unbound would have SQLite quietly read it as NULL.
    await db.execute('CREATE TABLE t (a INTEGER)');

    await expectLater(
      () => db.execute(
        'INSERT INTO t VALUES (?); INSERT INTO t VALUES (?)',
        args: [1],
      ),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('already run'),
        ),
      ),
    );

    // The refusal lands as that statement is reached, so the one before it
    // has already run and committed. Nothing is rolled back, which is why
    // the message has to say so rather than reading as a precondition.
    expect(await db.query('SELECT a FROM t'), [
      {'a': 1},
    ]);
  });

  test('every declared type survives the round trip', () async {
    await db.execute('''
      CREATE TABLE t (
        i INTEGER,
        r REAL,
        n NUMERIC,
        b BOOLEAN,
        s TEXT,
        d TIMESTAMP,
        j JSON,
        z BLOB
      )
    ''');
    final when = DateTime.utc(2026, 9, 19, 1, 2, 3);
    final bytes = Uint8List.fromList([1, 2, 3]);

    await db.execute(
      'INSERT INTO t VALUES (:i, :r, :n, :b, :s, :d, :j, :z)',
      params: {
        'i': 7,
        'r': 1.5,
        'n': '10.01',
        'b': true,
        's': 'hi',
        'd': when,
        'j': {'a': 1},
        'z': bytes,
      },
    );

    final row = (await db.query('SELECT * FROM t')).single;

    expect(row['i'], 7);
    expect(row['r'], 1.5);
    expect(row['n'], '10.01');
    expect(row['b'], isTrue);
    expect(row['s'], 'hi');
    expect(row['d'], when);
    expect((row['d'] as DateTime).isUtc, isTrue);
    expect(row['j'], {'a': 1});
    expect(row['z'], bytes);
  });

  test('a column with no declared type keeps its storage class', () async {
    final row = (await db.query("SELECT 1 AS i, 1.5 AS r, 'x' AS s")).single;

    expect(row['i'], 1);
    expect(row['r'], 1.5);
    expect(row['s'], 'x');
  });

  test('an empty blob reads back empty, not null', () async {
    // sqlite3_bind_blob takes a NULL pointer to mean a SQL NULL, so an empty
    // blob has to be handed a real one.
    await db.execute('CREATE TABLE t (z BLOB)');
    await db.execute('INSERT INTO t VALUES (:z)', params: {'z': Uint8List(0)});

    expect((await db.query('SELECT z FROM t')).single['z'], Uint8List(0));
  });

  test('a text column holding bytes that are not UTF-8 names the column', () {
    // SQLite never checks that a TEXT value is UTF-8, so the failure has to
    // arrive with the column attached rather than as a bare FormatException.
    expect(
      () => db.query("SELECT CAST(X'ff' AS TEXT) AS t"),
      throwsA(
        isA<SqliteDecodeException>()
            .having((e) => e.column, 'column', 't')
            .having((e) => e.message, 'message', contains('UTF-8')),
      ),
    );
  });

  test(
    'an aggregate over a timestamp column is text, not a DateTime',
    () async {
      // The declared type is the only hint SQLite gives, and an aggregate has
      // none. Documented, not fixed.
      await db.execute('CREATE TABLE t (d TIMESTAMP)');
      await db.execute(
        'INSERT INTO t VALUES (:d)',
        params: {'d': DateTime.utc(2026, 1, 1)},
      );

      final row = (await db.query('SELECT max(d) AS m FROM t')).single;

      expect(row['m'], isA<String>());
    },
  );

  test('a failing statement carries the extended result code', () async {
    await db.execute('CREATE TABLE t (a INTEGER PRIMARY KEY)');
    await db.execute('INSERT INTO t VALUES (1)');

    expect(
      () => db.execute('INSERT INTO t VALUES (1)'),
      throwsA(
        isA<SqliteException>()
            // SQLITE_CONSTRAINT_PRIMARYKEY
            .having((e) => e.extendedResultCode, 'extendedResultCode', 1555)
            // SQLITE_CONSTRAINT
            .having((e) => e.resultCode, 'resultCode', 19)
            .having((e) => e.sql, 'sql', contains('INSERT INTO t')),
      ),
    );
  });

  test('stays usable after a statement fails', () async {
    await db.execute('CREATE TABLE t (a INTEGER)');
    await expectLater(
      () => db.query('SELECT nope FROM t'),
      throwsA(isA<SqliteException>()),
    );

    expect(await db.query('SELECT 1 AS a'), [
      {'a': 1},
    ]);
  });

  test('opens a memory database, which has no WAL to turn on', () async {
    // The journal_mode check has to accept 'memory' as well as 'wal', or a
    // documented capability is unopenable. Nothing else in this file covers
    // that branch.
    final memory = await SqliteDatabase.open(':memory:');
    addTearDown(memory.close);

    await memory.execute('CREATE TABLE t (a INTEGER)');
    await memory.execute('INSERT INTO t VALUES (1)');

    expect(await memory.query('SELECT a FROM t'), [
      {'a': 1},
    ]);
  });

  test('close waits for a statement already running', () async {
    // An FFI call cannot be interrupted, so closing has to mean "stop once
    // you are done" rather than cutting the answer off.
    final counted = db.query(heavyQuery);

    await db.close();

    expect(await counted, [
      {'n': 2000000},
    ]);
  });

  test('runs a heavy query without stalling the event loop', () async {
    // The whole reason the driver goes through an isolate. Without it this
    // ticks zero times.
    var ticks = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => ticks++,
    );

    await db.query(heavyQuery);
    timer.cancel();

    expect(ticks, greaterThan(3));
  });
}
