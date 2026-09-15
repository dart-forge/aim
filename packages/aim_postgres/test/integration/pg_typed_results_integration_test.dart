@Tags(['integration'])
library;

import 'dart:typed_data';

import 'package:aim_postgres/aim_postgres.dart';
import 'package:test/test.dart';

void main() {
  late PostgresDatabase db;

  setUpAll(() async {
    db = await PostgresDatabase.connect(
      'postgresql://test:test@localhost:5433/test_db',
    );
    await db.execute('DROP TABLE IF EXISTS typed_results');
    await db.execute('''
      CREATE TABLE typed_results (
        id SERIAL PRIMARY KEY,
        i2 SMALLINT, i4 INT, i8 BIGINT,
        f4 REAL, f8 DOUBLE PRECISION, num NUMERIC(12, 4),
        b BOOLEAN, t TEXT, vc VARCHAR(20), ch CHAR(3), u UUID,
        ts TIMESTAMP, tstz TIMESTAMPTZ, d DATE, tm TIME, iv INTERVAL,
        j JSON, jb JSONB, by BYTEA,
        ia INT[], ta TEXT[], tsa TIMESTAMP[]
      )
    ''');
  });

  tearDownAll(() async {
    await db.execute('DROP TABLE IF EXISTS typed_results');
    await db.close();
  });

  setUp(() => db.execute('TRUNCATE typed_results'));

  group('scalar types come back as Dart values', () {
    test('SELECT literals', () async {
      final row = (await db.query('''
        SELECT 1::smallint AS i2, 2::int AS i4, 9223372036854775807::bigint AS i8,
               1.5::real AS f4, 2.25::double precision AS f8, 12.3400::numeric AS num,
               true AS b, 'x'::text AS t, 'y'::varchar AS vc, 'ab'::char(3) AS ch,
               '550e8400-e29b-41d4-a716-446655440000'::uuid AS u,
               '2024-01-02 03:04:05.123456'::timestamp AS ts,
               '2024-01-02 12:00:00+09'::timestamptz AS tstz,
               '2024-01-02'::date AS d, '12:34:56'::time AS tm, '1 day'::interval AS iv,
               '{"a": [1, null]}'::json AS j, '{"b": true}'::jsonb AS jb,
               '\\x00ff'::bytea AS by,
               ARRAY[1, NULL, 3] AS ia, ARRAY['a b', 'NULL', NULL]::text[] AS ta,
               NULL::int AS n
      '''))
          .single;

      expect(row['i2'], 1);
      expect(row['i4'], 2);
      expect(row['i8'], 9223372036854775807);
      expect(row['f4'], 1.5);
      expect(row['f8'], 2.25);
      expect(row['num'], '12.3400');
      expect(row['b'], isTrue);
      expect(row['t'], 'x');
      expect(row['vc'], 'y');
      expect(row['ch'], 'ab ');
      expect(row['u'], '550e8400-e29b-41d4-a716-446655440000');
      expect(row['ts'], DateTime.utc(2024, 1, 2, 3, 4, 5, 123, 456));
      expect((row['ts'] as DateTime).isUtc, isTrue);
      expect(row['tstz'], DateTime.utc(2024, 1, 2, 3, 0, 0));
      expect(row['d'], DateTime.utc(2024, 1, 2));
      expect(row['tm'], '12:34:56');
      expect(row['iv'], '1 day');
      expect(row['j'], {
        'a': [1, null],
      });
      expect(row['jb'], {'b': true});
      expect(row['by'], Uint8List.fromList([0x00, 0xff]));
      expect(row['ia'], [1, null, 3]);
      expect(row['ta'], ['a b', 'NULL', null]);
      expect(row['n'], isNull);
    });

    test('unknown types (enum) stay String', () async {
      await db.execute('DROP TYPE IF EXISTS mood_t');
      await db.execute("CREATE TYPE mood_t AS ENUM ('happy', 'sad')");
      try {
        final row = (await db.query("SELECT 'happy'::mood_t AS m")).single;
        expect(row['m'], 'happy');
      } finally {
        await db.execute('DROP TYPE mood_t');
      }
    });
  });

  group('parameters round-trip (A-045)', () {
    test('List, Map, Uint8List, DateTime, bool written with args and read back',
        () async {
      final at = DateTime.utc(2024, 5, 6, 7, 8, 9);
      final inserted = await db.execute(
        r'INSERT INTO typed_results (ia, ta, jb, by, ts, b, tsa) VALUES ($1, $2, $3, $4, $5, $6, $7)',
        args: [
          [1, null, 3],
          ['a b', 'c"d', r'e\f', null],
          {
            'k': [1, 2],
          },
          Uint8List.fromList([1, 2, 3]),
          at,
          true,
          [at, DateTime.utc(2024, 1, 1)],
        ],
      );
      expect(inserted, 1);

      final row =
          (await db.query('SELECT ia, ta, jb, by, ts, b, tsa FROM typed_results'))
              .single;
      expect(row['ia'], [1, null, 3]);
      expect(row['ta'], ['a b', 'c"d', r'e\f', null]);
      expect(row['jb'], {
        'k': [1, 2],
      });
      expect(row['by'], Uint8List.fromList([1, 2, 3]));
      expect(row['ts'], at);
      expect(row['b'], isTrue);
      expect(row['tsa'], [at, DateTime.utc(2024, 1, 1)]);
    });

    test('named params work the same way', () async {
      await db.execute(
        'INSERT INTO typed_results (ia, jb) VALUES (:ia, :jb)',
        params: {
          'ia': [4, 5],
          'jb': {'x': null},
        },
      );
      final row = (await db.query('SELECT ia, jb FROM typed_results')).single;
      expect(row['ia'], [4, 5]);
      expect(row['jb'], {'x': null});
    });
  });

  group('DateTime is UTC regardless of session time zone (A-044)', () {
    test('TIMESTAMP round-trips to the same instant with TIME ZONE Asia/Tokyo',
        () async {
      final at = DateTime.utc(2024, 3, 4, 5, 6, 7);
      // A transaction pins one pooled connection, so SET applies to the
      // same connection the INSERT and SELECT use.
      await db.transaction((tx) async {
        await tx.execute("SET TIME ZONE 'Asia/Tokyo'");
        // One placeholder per column: a single $1 used for three column
        // types would make PostgreSQL fail to infer the parameter type.
        await tx.execute(
          r'INSERT INTO typed_results (ts, tstz, d) VALUES ($1, $2, $3)',
          args: [at, at, at],
        );
        final row = (await tx.query('SELECT ts, tstz, d FROM typed_results')).single;
        expect(row['ts'], at);
        expect(row['tstz'], at);
        expect(row['d'], DateTime.utc(2024, 3, 4));
        for (final v in row.values) {
          expect((v as DateTime).isUtc, isTrue);
        }
        await tx.execute("SET TIME ZONE 'UTC'");
      });
    });

    test('a local DateTime is stored and read back as the same instant',
        () async {
      final local = DateTime(2024, 3, 4, 5, 6, 7); // whatever the test host zone is
      await db.execute(r'INSERT INTO typed_results (ts) VALUES ($1)', args: [local]);
      final row = (await db.query('SELECT ts FROM typed_results')).single;
      expect(row['ts'], local.toUtc());
    });
  });

  group('execute() returns affected rows (A-047)', () {
    test('INSERT / UPDATE / DELETE counts', () async {
      expect(
        await db.execute('INSERT INTO typed_results (i4) VALUES (1), (2), (3)'),
        3,
      );
      expect(await db.execute('UPDATE typed_results SET i4 = i4 + 1 WHERE i4 >= 2'), 2);
      expect(await db.execute('DELETE FROM typed_results WHERE i4 = 4'), 1);
      expect(await db.execute('DELETE FROM typed_results WHERE i4 = 999'), 0);
    });

    test('DDL reports 0', () async {
      expect(await db.execute('CREATE TEMP TABLE tmp_x (a INT)'), 0);
    });

    test('several statements in one Simple Query are summed', () async {
      expect(
        await db.execute(
          'INSERT INTO typed_results (i4) VALUES (1), (2); '
          'INSERT INTO typed_results (i4) VALUES (3); '
          'UPDATE typed_results SET i4 = 0',
        ),
        2 + 1 + 3,
      );
    });

    test('inside a transaction', () async {
      final n = await db.transaction(
        (tx) => tx.execute('INSERT INTO typed_results (i4) VALUES (1), (2)'),
      );
      expect(n, 2);
    });

    test('query() with RETURNING still returns rows', () async {
      final rows = await db.query(
        'INSERT INTO typed_results (i4) VALUES (7) RETURNING id, i4',
      );
      expect(rows.single['i4'], 7);
      expect(rows.single['id'], isA<int>());
    });
  });

  group('multi-statement Simple Query does not corrupt connection state (F1)', () {
    test('query() returns the rows of the last row-returning statement', () async {
      final before = db.poolStats.destroyed;
      final rows = await db.query("SELECT 1 AS a, 2 AS b; SELECT 'x' AS c");
      expect(rows, [{'c': 'x'}]);
      expect(db.poolStats.destroyed, before);
    });

    test('execute() sums affected rows from several SELECTs', () async {
      expect(
        await db.execute("SELECT 1 AS a, 2 AS b; SELECT 'x' AS c"),
        2,
      );
    });
  });

  group('decode failures (A-046)', () {
    test("'infinity'::timestamp throws PostgresDecodeException and the connection survives",
        () async {
      final before = db.poolStats.destroyed;
      await expectLater(
        db.query("SELECT 'infinity'::timestamp AS ts"),
        throwsA(
          isA<PostgresDecodeException>()
              .having((e) => e.columnName, 'columnName', 'ts')
              .having((e) => e.rawValue, 'rawValue', 'infinity'),
        ),
      );
      // The pool must not have discarded the connection (A-046).
      final row = (await db.query('SELECT 1 AS v')).single;
      expect(row['v'], 1);
      expect(db.poolStats.destroyed, before);
    });

    test('inside a transaction the connection is still usable after the failure',
        () async {
      await db.transaction((tx) async {
        await expectLater(
          tx.query("SELECT 'infinity'::timestamp AS ts"),
          throwsA(isA<PostgresDecodeException>()),
        );
        final row = (await tx.query('SELECT 2 AS v')).single;
        expect(row['v'], 2);
      });
    });
  });
}
