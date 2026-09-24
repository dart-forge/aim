@Tags(['integration'])
library;

import 'dart:typed_data';

import 'package:aim_mysql/aim_mysql.dart';
// mysqlClosedMessage is an internal wording convention, not part of the
// public contract, so the barrel above does not export it -- this test
// reaches into src/ for it the way only code inside this package can.
import 'package:aim_mysql/src/exceptions.dart' show mysqlClosedMessage;
import 'package:rig_mysql/rig_mysql.dart';
import 'package:test/test.dart';

void main() {
  final lease = useMySql();
  late MySqlDatabase db;

  setUp(() async {
    db = await MySqlDatabase.connect(
      '${lease.url}?sslmode=disable&allowPublicKeyRetrieval=true',
    );
    await db.execute('DROP TABLE IF EXISTS people');
    await db.execute('''
      CREATE TABLE people (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(50) NOT NULL,
        active BOOL NOT NULL DEFAULT TRUE
      )
    ''');
  });

  tearDown(() => db.close());

  test('query returns maps keyed by column name', () async {
    await db.execute(
      'INSERT INTO people (name) VALUES (:name)',
      params: {'name': 'Ada'},
    );

    final rows = await db.query('SELECT id, name, active FROM people');

    expect(rows, hasLength(1));
    expect(rows.single['name'], 'Ada');
    expect(rows.single['active'], isTrue);
    expect(rows.single['id'], isA<int>());
  });

  test('execute returns the number of rows affected', () async {
    await db.execute(
      'INSERT INTO people (name) VALUES (:a), (:b)',
      params: {'a': 'Ada', 'b': 'Grace'},
    );

    expect(
      await db.execute('UPDATE people SET active = :v', params: {'v': false}),
      2,
    );
  });

  test('execute returns zero for a statement with no row count', () async {
    expect(await db.execute('CREATE TABLE counted (a INT)'), 0);
  });

  test('positional args work as well as named params', () async {
    await db.execute('INSERT INTO people (name) VALUES (?)', args: ['Ada']);

    expect(
      (await db.query(
        'SELECT name FROM people WHERE name = ?',
        args: ['Ada'],
      )).single['name'],
      'Ada',
    );
  });

  test('passing both params and args is refused', () async {
    // They cannot both be right, and picking one silently would bind the
    // wrong values.
    await expectLater(
      db.query('SELECT :a', params: {'a': 1}, args: [1]),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('insert returns the generated id', () async {
    // MySQL has no RETURNING, so this is the only way to get it.
    final first = await db.insert(
      'INSERT INTO people (name) VALUES (:name)',
      params: {'name': 'Ada'},
    );
    final second = await db.insert(
      'INSERT INTO people (name) VALUES (:name)',
      params: {'name': 'Grace'},
    );

    expect(first, greaterThan(0));
    expect(second, first + 1);
  });

  test('insert returns zero when nothing was generated', () async {
    await db.execute('CREATE TABLE no_auto (id INT PRIMARY KEY)');

    expect(
      await db.insert('INSERT INTO no_auto VALUES (:id)', params: {'id': 5}),
      0,
    );
  });

  test('a value read from one query can be passed to the next', () async {
    // The contract says so, and it is the thing that breaks when an encoder
    // and a decoder disagree.
    await db.execute('''
      CREATE TABLE every_type (
        id INT PRIMARY KEY,
        s VARCHAR(50), b VARBINARY(20), d DATETIME(6),
        `dec` DECIMAL(10, 4), j JSON, flag BOOL, n BIGINT, x DOUBLE
      )
    ''');
    await db.execute(
      'INSERT INTO every_type VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      args: [
        1,
        '日本語',
        Uint8List.fromList([0x00, 0xff]),
        DateTime.utc(2024, 9, 22, 14, 30, 45, 123, 456),
        '12.3456',
        '{"a": 1}',
        true,
        -9007199254740993,
        1.5,
      ],
    );

    final original = (await db.query('SELECT * FROM every_type')).single;

    await db.execute(
      'INSERT INTO every_type VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      args: [
        2,
        original['s'],
        original['b'],
        original['d'],
        original['dec'],
        // JSON comes back decoded, and goes back as the JSON text.
        '{"a": 1}',
        original['flag'],
        original['n'],
        original['x'],
      ],
    );

    final copy = (await db.query('SELECT * FROM every_type WHERE id = 2'))
        .single;

    for (final key in ['s', 'b', 'd', 'dec', 'flag', 'n', 'x']) {
      expect(copy[key], original[key], reason: key);
    }
  });

  test('changing sql_mode changes how the next statement is scanned', () async {
    // The driver reads sql_mode once when it connects. Without noticing
    // this SET, it would keep scanning with the old rule and a literal
    // containing a backslash would end in the wrong place -- the SQL breaks
    // silently, which is very hard to trace back to here.
    //
    // :id has to sit AFTER the tricky literal, not before it: a
    // placeholder found before the literal is found the same way under
    // either dialect, so a version of this test with :id first (as an
    // earlier version of this test had it) cannot fail even if sql_mode is
    // never re-read at all. Under the default dialect, the backslash
    // would escape the closing quote, the literal would swallow
    // ", :t)" looking for a real one, and :t would never be found as a
    // placeholder -- the rewritten SQL would still read ":t)" verbatim and
    // the server would refuse it with errno 1064 near ":t)". Only under
    // NO_BACKSLASH_ESCAPES does the literal end where it looks like it
    // does and :t get bound.
    await db.execute('DROP TABLE IF EXISTS modes2');
    await db.execute('''
      CREATE TABLE modes2 (id INT PRIMARY KEY, s VARCHAR(50), t VARCHAR(50))
    ''');

    await db.transaction((tx) async {
      await tx.execute("SET SESSION sql_mode = 'NO_BACKSLASH_ESCAPES'");

      await tx.execute(
        r"INSERT INTO modes2 VALUES (:id, 'a\', :t)",
        params: {'id': 1, 't': 'b'},
      );
    });

    final row = (await db.query('SELECT id, t FROM modes2')).single;
    expect(row['id'], 1);
    expect(row['t'], 'b');
  });

  test(
    'a bare SET autocommit = 0 gets its connection discarded, not recycled',
    () async {
      // A single connection, so the next call can only be handed back this
      // exact physical connection or a freshly opened one -- there is
      // nowhere else for it to come from.
      final solo = await MySqlDatabase.connect(
        '${lease.url}?sslmode=disable&allowPublicKeyRetrieval=true',
        maxConnections: 1,
      );
      addTearDown(solo.close);
      await solo.execute('DROP TABLE IF EXISTS autocommit_t');
      await solo.execute(
        'CREATE TABLE autocommit_t (id INT PRIMARY KEY) ENGINE = InnoDB',
      );
      final destroyedBefore = solo.poolStats.destroyed;

      // SET routes through the text protocol and is not blocked the way a
      // bare START TRANSACTION is (errno 1295) -- it just quietly leaves
      // the connection not auto-committing. The INSERT that follows then
      // opens an explicit transaction on it.
      await solo.execute('SET autocommit = 0');
      await solo.execute('INSERT INTO autocommit_t VALUES (1)');

      expect(
        solo.poolStats.destroyed,
        greaterThan(destroyedBefore),
        reason:
            'a connection released while a transaction is open on it must '
            'be discarded -- handing it back would poison whichever '
            'unrelated caller the pool gives it to next',
      );

      // The replacement connection the pool opens next comes back clean.
      // A recycled, still-poisoned connection would answer OFF here.
      final rows = await solo.query("SHOW VARIABLES LIKE 'autocommit'");
      expect(rows.single['Value'], 'ON');
    },
  );

  test(
    'a caller after SET autocommit = 0 gets a real, durable insert -- not '
    "one the poisoned connection's own discard silently rolls back",
    () async {
      // The connection [SET autocommit = 0] itself ran on must never be
      // handed to a later, unrelated caller: if it were, that caller's own
      // INSERT would implicitly open a transaction it never asked for, get
      // reported as a normal success, and then be rolled back by the
      // server the moment this driver discards the connection out from
      // under it -- a caller-visible success that silently did not
      // happen. Discarding the connection right after the SET itself,
      // before anything else ever borrows it, is what this test pins:
      // it must never even reach the INSERT below.
      final solo = await MySqlDatabase.connect(
        '${lease.url}?sslmode=disable&allowPublicKeyRetrieval=true',
        maxConnections: 1,
      );
      addTearDown(solo.close);
      await solo.execute('DROP TABLE IF EXISTS poisoned_insert_t');
      await solo.execute(
        'CREATE TABLE poisoned_insert_t (id INT PRIMARY KEY) ENGINE = InnoDB',
      );

      await solo.execute('SET autocommit = 0');
      await solo.execute('INSERT INTO poisoned_insert_t VALUES (1)');

      final rows = await solo.query('SELECT * FROM poisoned_insert_t');
      expect(
        rows,
        hasLength(1),
        reason:
            'the INSERT ran on a fresh, autocommit-ON connection and must '
            'still be there for a later caller to see',
      );
    },
  );

  test('any SET -- not just autocommit -- gets its connection discarded, so '
      'session state never leaks to the next borrower', () async {
    // time_zone is the concrete case that matters: it changes how every
    // later TIMESTAMP on this connection is read back, and nothing
    // about SET time_zone looks like an open transaction the way SET
    // autocommit = 0 does, so this exercises a different path than the
    // autocommit-specific tests above.
    final solo = await MySqlDatabase.connect(
      '${lease.url}?sslmode=disable&allowPublicKeyRetrieval=true',
      maxConnections: 1,
    );
    addTearDown(solo.close);
    final destroyedBefore = solo.poolStats.destroyed;

    await solo.execute("SET time_zone = '+09:00'");

    expect(solo.poolStats.destroyed, greaterThan(destroyedBefore));

    // The replacement connection comes back with this driver's own
    // pinned zone, not the one the earlier caller set.
    final rows = await solo.query('SELECT @@session.time_zone AS tz');
    expect(rows.single['tz'], '+00:00');
  });

  test('a SET preceded by a comment is still recognised as a SET', () async {
    final solo = await MySqlDatabase.connect(
      '${lease.url}?sslmode=disable&allowPublicKeyRetrieval=true',
      maxConnections: 1,
    );
    addTearDown(solo.close);
    final destroyedBefore = solo.poolStats.destroyed;

    await solo.execute("/* comment */ SET time_zone = '+09:00'");

    expect(
      solo.poolStats.destroyed,
      greaterThan(destroyedBefore),
      reason:
          'a leading comment must not hide the SET from the check that '
          'discards the connection',
    );
  });

  test('the pool hands out more than one connection', () async {
    // connect opens one; four overlapping queries have to open more, which
    // is also the only thing here that exercises two connections at once.
    await Future.wait([
      for (var i = 0; i < 4; i++) db.query('SELECT SLEEP(0.1)'),
    ]);

    expect(db.poolStats.total, greaterThan(1));
  });

  test('a closed database refuses further work with one wording', () async {
    await db.close();

    await expectLater(
      db.query('SELECT 1'),
      throwsA(
        isA<StateError>().having(
          (e) => e.toString(),
          'toString',
          contains(mysqlClosedMessage),
        ),
      ),
    );
  });
}
