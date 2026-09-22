@Tags(['integration'])
library;

import 'dart:typed_data';

import 'package:aim_mysql/src/connection.dart';
import 'package:aim_mysql/src/exceptions.dart';
import 'package:aim_mysql/src/statement.dart';
import 'package:rig_mysql/rig_mysql.dart';
import 'package:test/test.dart';

void main() {
  final lease = useMySql();
  late MySqlConnection connection;

  setUp(() async {
    connection = await MySqlConnection.connect(
      MySqlConnectionSettings.parse('${lease.url}?sslmode=disable'),
    );
  });

  tearDown(() => connection.close());

  Future<MySqlResultSets> run(
    String sql, [
    List<Object?> values = const [],
  ]) async {
    final statement = await connection.statements.get(sql);
    return executeStatement(connection, statement, values);
  }

  /// The one result set that has rows. Throws when a statement produced
  /// none, which in these tests means the test asked the wrong thing.
  Future<MySqlResult> rowsOf(
    String sql, [
    List<Object?> values = const [],
  ]) async => (await run(sql, values)).withRows!;

  test('a statement with no parameters returns rows', () async {
    final result = await rowsOf('SELECT 1 AS one');

    expect(result.columns.single.name, 'one');
    expect(result.rows, [
      [1],
    ]);
  });

  test('parameters are bound in order', () async {
    expect((await rowsOf('SELECT ?, ?', ['a', 'b'])).rows.single, ['a', 'b']);
  });

  test('a NULL parameter round-trips', () async {
    expect((await rowsOf('SELECT ? IS NULL', [null])).rows.single.single, 1);
  });

  test('every type this driver sends comes back as itself', () async {
    // The round trip is the only thing that proves the encoder and the
    // decoder agree, rather than being wrong in the same direction.
    await run('''
      CREATE TABLE roundtrip (
        id INT PRIMARY KEY,
        flag BOOL,
        n BIGINT,
        x DOUBLE,
        s VARCHAR(50),
        b VARBINARY(50),
        d DATETIME(6),
        amount DECIMAL(10, 4),
        j JSON
      )
    ''');

    await run('INSERT INTO roundtrip VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', [
      1,
      true,
      -9007199254740993,
      1.5,
      '日本語',
      Uint8List.fromList([0x00, 0xff]),
      DateTime.utc(2024, 9, 22, 14, 30, 45, 123, 456),
      '12.3456',
      '{"a": 1}',
    ]);

    final row = (await rowsOf('SELECT * FROM roundtrip WHERE id = ?', [
      1,
    ])).rows.single;

    expect(row[1], isTrue);
    expect(row[2], -9007199254740993);
    expect(row[3], 1.5);
    expect(row[4], '日本語');
    expect(row[5], [0x00, 0xff]);
    expect(row[6], DateTime.utc(2024, 9, 22, 14, 30, 45, 123, 456));
    expect(row[7], '12.3456');
    expect(row[8], {'a': 1});
  });

  test('a TIMESTAMP comes back as the UTC instant it was written as', () async {
    // The point of pinning time_zone. Without it the server would
    // interpret the value in its own zone and hand back a different
    // instant.
    await run('CREATE TABLE stamps (id INT PRIMARY KEY, at TIMESTAMP)');
    await run('INSERT INTO stamps VALUES (?, ?)', [
      1,
      DateTime.utc(2024, 9, 22, 14, 30, 45),
    ]);

    final at = (await rowsOf('SELECT at FROM stamps')).rows.single.single;

    expect(at, DateTime.utc(2024, 9, 22, 14, 30, 45));
    expect((at as DateTime).isUtc, isTrue);
  });

  test(
    'TIMESTAMP and DATETIME differ, and pinning the zone is what hides it',
    () async {
      // The server converts a TIMESTAMP between the session's zone and UTC
      // storage; a DATETIME is stored verbatim. With time_zone pinned to
      // +00:00 the two read back identically, which is the whole reason the
      // connection pins it. Unpinning it here shows what the driver would be
      // handing back otherwise: the same stored instant, labelled UTC, an
      // hour count off.
      await run('DROP TABLE IF EXISTS zones');
      await run('''
      CREATE TABLE zones (id INT PRIMARY KEY, dt DATETIME, ts TIMESTAMP)
    ''');
      final written = DateTime.utc(2024, 9, 22, 14, 30, 45);
      await run('INSERT INTO zones VALUES (?, ?, ?)', [1, written, written]);

      final pinned = (await rowsOf('SELECT dt, ts FROM zones')).rows.single;
      expect(pinned[0], written);
      expect(pinned[1], written, reason: 'identical while the zone is pinned');

      await connection.runTextQuery("SET SESSION time_zone = '+09:00'");
      final shifted = (await rowsOf('SELECT dt, ts FROM zones')).rows.single;

      expect(shifted[0], written, reason: 'a DATETIME does not move');
      expect(
        shifted[1],
        isNot(written),
        reason: 'a TIMESTAMP does, which is what the pinning prevents',
      );
      expect(
        shifted[1],
        written.add(const Duration(hours: 9)),
        reason: 'by exactly the offset, read back as if it were UTC',
      );
    },
  );

  test('a statement is prepared once however often it runs', () async {
    await run('SELECT 1');
    final size = connection.statements.size;

    await run('SELECT 1');
    await run('SELECT 1');

    expect(connection.statements.size, size);
  });

  test('a schema change does not break the statements after it', () async {
    // What this actually establishes is that adding a column does not
    // leave a cached statement returning stale results -- and the reason
    // it holds is that every execute reply carries fresh column
    // definitions, which this driver reads.
    //
    // It is NOT evidence that the re-prepare path works. Error 1615 could
    // not be provoked on 8.0 or 8.4 by any of eight schema changes tried:
    // adding a column, dropping and recreating, changing a column's type,
    // converting the charset, swapping via RENAME TABLE, truncating,
    // adding an AUTO_INCREMENT primary key so the column order shifts, and
    // redefining a view. The server absorbed all of them silently. The
    // retry is kept because the protocol specifies it and it costs
    // nothing. Its mechanics are covered by the unit tests for the retry
    // policy (see withReprepareRetry in statement_test.dart), not by this
    // test.
    await run('CREATE TABLE evolving (a INT)');
    await run('INSERT INTO evolving VALUES (?)', [1]);
    await run('SELECT * FROM evolving');

    await run('ALTER TABLE evolving ADD COLUMN b INT');

    final result = await rowsOf('SELECT * FROM evolving');

    expect(result.columns.map((c) => c.name), ['a', 'b']);
  });

  test('INSERT reports the affected row count and the generated id', () async {
    // Both are only exercised for the no-rows shape elsewhere in this
    // file; reading back a generated id is an entirely ordinary thing for
    // a caller to do, so the pass-through itself is worth asserting on a
    // real value, not just on the absence of rows.
    await run('DROP TABLE IF EXISTS autoinc_t');
    await run(
      'CREATE TABLE autoinc_t (id INT AUTO_INCREMENT PRIMARY KEY, val INT)',
    );

    final first = await run('INSERT INTO autoinc_t (val) VALUES (?)', [10]);
    expect(first.totalAffectedRows, 1);
    expect(first.lastInsertId, 1);

    final second = await run('INSERT INTO autoinc_t (val) VALUES (?)', [20]);
    expect(second.totalAffectedRows, 1);
    expect(second.lastInsertId, 2);
  });

  test('an UPDATE affecting several rows reports the real count', () async {
    await run('DROP TABLE IF EXISTS bulk_t');
    await run('CREATE TABLE bulk_t (id INT PRIMARY KEY, val INT)');
    await run('INSERT INTO bulk_t VALUES (?, ?)', [1, 0]);
    await run('INSERT INTO bulk_t VALUES (?, ?)', [2, 0]);
    await run('INSERT INTO bulk_t VALUES (?, ?)', [3, 0]);

    final result = await run('UPDATE bulk_t SET val = ?', [99]);

    expect(result.totalAffectedRows, 3);
  });

  test('a duplicate key is reported as a unique violation', () async {
    await run('CREATE TABLE unique_t (id INT PRIMARY KEY)');
    await run('INSERT INTO unique_t VALUES (?)', [1]);

    await expectLater(
      run('INSERT INTO unique_t VALUES (?)', [1]),
      throwsA(isA<MySqlUniqueViolation>()),
    );
  });

  test('and the connection still works afterwards', () async {
    // An error is not a desync: the driver has to be able to carry on.
    await run('CREATE TABLE still_ok (id INT PRIMARY KEY)');
    await run('INSERT INTO still_ok VALUES (?)', [1]);
    await expectLater(
      run('INSERT INTO still_ok VALUES (?)', [1]),
      throwsA(isA<MySqlUniqueViolation>()),
    );

    expect(
      (await rowsOf('SELECT COUNT(*) FROM still_ok')).rows.single.single,
      1,
    );
  });

  test('a procedure returning two result sets is read to the end', () async {
    // Leaving the second one unread desynchronises the connection for good,
    // and the next statement on it reads the leftovers as its own answer.
    // The assertion after this one is what would catch that.
    await connection.runTextQuery('DROP PROCEDURE IF EXISTS two_sets');
    await connection.runTextQuery('''
      CREATE PROCEDURE two_sets()
      BEGIN
        SELECT 1 AS a;
        SELECT 2 AS b;
      END
    ''');

    final sets = await run('CALL two_sets()');

    expect(sets.sets.where((s) => s.rows.isNotEmpty), hasLength(2));
    expect((await rowsOf('SELECT 3 AS c')).rows.single.single, 3);
  });

  test(
    'two result sets with rows is an error, not a silent first one',
    () async {
      // query() hands back one list, so returning the first and dropping the
      // second would hide rows the server sent.
      await connection.runTextQuery('DROP PROCEDURE IF EXISTS two_sets_rows');
      await connection.runTextQuery('''
      CREATE PROCEDURE two_sets_rows()
      BEGIN
        SELECT 1 AS a;
        SELECT 2 AS b;
      END
    ''');

      final sets = await run('CALL two_sets_rows()');

      expect(() => sets.withRows, throwsA(isA<MySqlProtocolException>()));
    },
  );

  test('a zero date fails to decode rather than becoming null', () async {
    // Inserting one needs a permissive sql_mode: the default refuses it.
    // Which is also the point -- a table that already holds one was written
    // under that mode, and the driver still has to read it honestly.
    await run('DROP TABLE IF EXISTS zero_dates');
    await run('CREATE TABLE zero_dates (id INT PRIMARY KEY, d DATE)');
    await connection.runTextQuery(
      "SET SESSION sql_mode = 'ALLOW_INVALID_DATES'",
    );
    await run('INSERT INTO zero_dates VALUES (?, ?)', [1, '0000-00-00']);

    await expectLater(
      run('SELECT d FROM zero_dates'),
      throwsA(isA<MySqlDecodeException>()),
    );
  });

  test('BLOB and TEXT are told apart, though they share a type byte', () async {
    await run('DROP TABLE IF EXISTS blobs_and_texts');
    await run('''
      CREATE TABLE blobs_and_texts (id INT PRIMARY KEY, b BLOB, t TEXT)
    ''');
    await run('INSERT INTO blobs_and_texts VALUES (?, ?, ?)', [
      1,
      Uint8List.fromList([0x00, 0xff, 0x80]),
      'text',
    ]);

    final row = (await rowsOf('SELECT b, t FROM blobs_and_texts')).rows.single;

    expect(row[0], isA<Uint8List>());
    expect(row[0], [0x00, 0xff, 0x80]);
    expect(row[1], 'text');
  });

  test('a payload larger than one packet round-trips both ways', () async {
    // 16MB is where a packet has to be split, so this exercises splitting
    // on the way out and reassembly on the way back.
    //
    // The exact-multiple case -- a length of 0xffffff, which needs an empty
    // packet after it to say the payload ended -- is not reachable from
    // here: the packet is the payload plus a command byte, a statement id,
    // flags, a bitmap, type bytes and a length prefix, so hitting it would
    // mean computing that overhead and would break the moment it changed.
    // A dedicated wire-level test covers it where the length is the thing
    // under test.
    await run('CREATE TABLE big (id INT PRIMARY KEY, payload LONGBLOB)');
    final payload = Uint8List(0x1000000 + 1000);

    await run('INSERT INTO big VALUES (?, ?)', [1, payload]);

    final back = (await rowsOf('SELECT payload FROM big')).rows.single.single;

    expect(back, hasLength(payload.length));
  });
}
