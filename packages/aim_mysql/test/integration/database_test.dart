@Tags(['integration'])
library;

import 'dart:typed_data';

import 'package:aim_mysql/aim_mysql.dart';
import 'package:rig_mysql/rig_mysql.dart';
import 'package:test/test.dart';

void main() {
  final lease = useMySql();
  late MySqlDatabase db;

  setUp(() async {
    db = await MySqlDatabase.connect('${lease.url}?sslmode=disable');
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
    await db.execute('DROP TABLE IF EXISTS modes');
    await db.execute('CREATE TABLE modes (id INT PRIMARY KEY, s VARCHAR(50))');

    await db.transaction((tx) async {
      await tx.execute("SET SESSION sql_mode = 'NO_BACKSLASH_ESCAPES'");

      // With NO_BACKSLASH_ESCAPES the literal ends at the second quote, so
      // :id is a placeholder. Under the default it would be inside the
      // literal and there would be nothing to bind.
      await tx.execute(
        r"INSERT INTO modes VALUES (:id, 'a\')",
        params: {'id': 1},
      );
    });

    expect((await db.query('SELECT id FROM modes')).single['id'], 1);
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
