@Tags(['integration'])
library;

import 'package:aim_postgres/aim_postgres.dart';
import 'package:test/test.dart';

import 'docker_stack.dart';

const _port = 15433;
const _url = 'postgresql://test:test@localhost:$_port/test_db';

Future<int> _pid(PostgresQueryable q) async {
  final rows = await q.query('SELECT pg_backend_pid() AS pid');
  return rows.single['pid'] as int;
}

void main() {
  // A separate raw connection used to kill backends from "outside".
  late PostgresConnection admin;

  setUpAll(() async {
    await ensurePostgresStack();
    admin = await reportPortIfTaken(
      () => PostgresConnection.connect(_url),
      port: _port,
    );
  });

  tearDownAll(() => admin.close());

  Future<void> terminate(int pid) async {
    await admin.sendSimpleQuery('SELECT pg_terminate_backend($pid)');
    // Give the server a moment to close the victim's socket.
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  group('PostgresDatabase.connect', () {
    test('rejects invalid pool options', () async {
      await expectLater(
        PostgresDatabase.connect(_url, maxConnections: 0),
        throwsArgumentError,
      );
    });

    test('fails fast on a bad connection string', () async {
      await expectLater(
        PostgresDatabase.connect(
          'postgresql://test:wrong@localhost:15433/test_db',
        ),
        throwsA(isA<QueryException>()),
      );
    });

    test('opens exactly one connection eagerly', () async {
      final db = await PostgresDatabase.connect(_url);
      expect(db.poolStats.total, 1);
      expect(db.poolStats.idle, 1);
      await db.close();
    });
  });

  group('concurrency', () {
    test('30 concurrent queries share at most maxConnections backends',
        () async {
      final db = await PostgresDatabase.connect(_url, maxConnections: 3);
      try {
        final pids = await Future.wait(List.generate(
          30,
          (_) => db
              .query('SELECT pg_sleep(0.02), pg_backend_pid() AS pid')
              .then((rows) => rows.single['pid'] as int),
        ));
        expect(pids, hasLength(30));
        expect(pids.toSet().length, lessThanOrEqualTo(3));
        expect(pids.toSet().length, greaterThan(1),
            reason: 'queries actually ran on more than one connection');
        expect(db.poolStats.total, lessThanOrEqualTo(3));
        expect(db.poolStats.inUse, 0);
      } finally {
        await db.close();
      }
    });

    test('queries inside one transaction are serialized on one connection',
        () async {
      final db = await PostgresDatabase.connect(_url);
      try {
        final result = await db.transaction((tx) => Future.wait([
              tx.query('SELECT 1 AS v'),
              tx.query('SELECT 2 AS v'),
              tx.query('SELECT 3 AS v'),
            ]));
        expect(result.map((r) => r.single['v']).toList(), [1, 2, 3]);
      } finally {
        await db.close();
      }
    });
  });

  group('transaction pinning', () {
    test('uses one backend for the whole callback, another for outer queries',
        () async {
      final db = await PostgresDatabase.connect(_url);
      try {
        late int inner1, inner2, outer;
        await db.transaction((tx) async {
          inner1 = await _pid(tx);
          outer = await _pid(db);
          inner2 = await _pid(tx);
        });
        expect(inner1, inner2);
        expect(outer, isNot(inner1));
        expect(db.poolStats.total, 2);
      } finally {
        await db.close();
      }
    });

    test('rolls back on error and keeps the connection', () async {
      // TEMP tables are per-backend, so pin everything to one connection.
      final single = await PostgresDatabase.connect(_url, maxConnections: 1);
      try {
        await single.execute('CREATE TEMP TABLE pool_tx (v INT)');
        await expectLater(
          single.transaction((tx) async {
            await tx.execute('INSERT INTO pool_tx VALUES (1)');
            throw StateError('boom');
          }),
          throwsStateError,
        );
        final rows = await single.query('SELECT count(*) AS c FROM pool_tx');
        expect(rows.single['c'], 0);
        expect(single.poolStats.destroyed, 0);
      } finally {
        await single.close();
      }
    });
  });

  group('broken connections', () {
    test('an idle backend killed externally is replaced on next acquire',
        () async {
      final db = await PostgresDatabase.connect(
        _url,
        maxConnections: 1,
        validationInterval: Duration.zero,
      );
      try {
        final pid = await _pid(db);
        await terminate(pid);

        final rows = await db.query('SELECT 1 AS v');
        expect(rows.single['v'], 1);
        expect(db.poolStats.validationFailures, 1);
        expect(db.poolStats.destroyed, 1);
        expect(db.poolStats.created, 2);
      } finally {
        await db.close();
      }
    });

    test('an in-use backend killed externally fails that call and is discarded',
        () async {
      final db = await PostgresDatabase.connect(_url, maxConnections: 1);
      try {
        await expectLater(
          db.transaction((tx) async {
            final pid = await _pid(tx);
            await terminate(pid);
            await tx.query('SELECT 1');
          }),
          throwsA(isNot(isA<QueryException>())),
        );
        expect(db.poolStats.destroyed, 1);

        final rows = await db.query('SELECT 2 AS v');
        expect(rows.single['v'], 2);
        expect(db.poolStats.created, 2);
      } finally {
        await db.close();
      }
    });

    test('a server error does not discard the connection', () async {
      final db = await PostgresDatabase.connect(_url, maxConnections: 1);
      try {
        await expectLater(
          db.query('SELECT * FROM table_that_does_not_exist'),
          throwsA(isA<QueryException>()),
        );
        expect(db.poolStats.destroyed, 0);
        final rows = await db.query('SELECT 3 AS v');
        expect(rows.single['v'], 3);
        expect(db.poolStats.created, 1);
      } finally {
        await db.close();
      }
    });
  });

  group('close', () {
    test('query after close throws StateError', () async {
      final db = await PostgresDatabase.connect(_url);
      await db.close();
      await expectLater(db.query('SELECT 1'), throwsStateError);
      await expectLater(
        db.transaction((tx) => tx.query('SELECT 1')),
        throwsStateError,
      );
    });

    test('acquire timeout surfaces as PoolTimeoutException', () async {
      final db = await PostgresDatabase.connect(
        _url,
        maxConnections: 1,
        acquireTimeout: const Duration(milliseconds: 200),
      );
      try {
        final blocker = db.transaction((tx) async {
          await tx.query('SELECT pg_sleep(1)');
        });
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await expectLater(
          db.query('SELECT 1'),
          throwsA(isA<PoolTimeoutException>()),
        );
        await blocker;
        expect(db.poolStats.timeouts, 1);
      } finally {
        await db.close();
      }
    });
  });

  group('session hygiene', () {
    test('a connection left inside a transaction is discarded, not reused',
        () async {
      final db = await PostgresDatabase.connect(_url, maxConnections: 1);
      try {
        await db.execute('BEGIN');
        expect(db.poolStats.destroyed, 1);
        expect(db.poolStats.idle, 0);
        // The next call gets a fresh connection with no open transaction.
        final rows = await db.query('SELECT 1 AS v');
        expect(rows.single['v'], 1);
        expect(db.poolStats.created, 2);
      } finally {
        await db.close();
      }
    });

    test('a normal transaction leaves the connection reusable', () async {
      final db = await PostgresDatabase.connect(_url, maxConnections: 1);
      try {
        await db.transaction((tx) => tx.query('SELECT 1'));
        expect(db.poolStats.destroyed, 0);
        expect(db.poolStats.idle, 1);
      } finally {
        await db.close();
      }
    });
  });

  group('PostgresConnection state', () {
    test('a server error leaves the connection usable and not broken', () async {
      final conn = await PostgresConnection.connect(_url);
      try {
        await expectLater(
          conn.sendSimpleQuery('SELECT * FROM no_such_table_xyz'),
          throwsA(isA<QueryException>()),
        );
        expect(conn.isBroken, isFalse);
        final result = await conn.sendSimpleQuery('SELECT 1 AS v');
        expect(result.toMaps().single['v'], 1);
      } finally {
        await conn.close();
      }
    });

    test('a terminated backend marks the connection broken', () async {
      final conn = await PostgresConnection.connect(_url);
      final pid = (await conn.sendSimpleQuery('SELECT pg_backend_pid() AS pid'))
          .toMaps()
          .single['pid'] as int;
      await terminate(pid);
      await expectLater(
        conn.sendSimpleQuery('SELECT 1'),
        throwsA(isNot(isA<QueryException>())),
      );
      expect(conn.isBroken, isTrue);
      await conn.close();
      expect(conn.isClosed, isTrue);
    });

    test('tracks transaction status from ReadyForQuery', () async {
      final conn = await PostgresConnection.connect(_url);
      try {
        expect(conn.inTransaction, isFalse);
        await conn.sendSimpleQuery('BEGIN');
        expect(conn.transactionStatus, 'T');
        await expectLater(
          conn.sendSimpleQuery('SELECT * FROM no_such_table_xyz'),
          throwsA(isA<QueryException>()),
        );
        expect(conn.transactionStatus, 'E');
        await conn.sendSimpleQuery('ROLLBACK');
        expect(conn.transactionStatus, 'I');
      } finally {
        await conn.close();
      }
    });

    test('ping returns false on a terminated backend', () async {
      final conn = await PostgresConnection.connect(_url);
      expect(await conn.ping(), isTrue);
      final pid = (await conn.sendSimpleQuery('SELECT pg_backend_pid() AS pid'))
          .toMaps()
          .single['pid'] as int;
      await terminate(pid);
      expect(await conn.ping(), isFalse);
      expect(conn.isBroken, isTrue);
      await conn.close();
    });
  });
}
