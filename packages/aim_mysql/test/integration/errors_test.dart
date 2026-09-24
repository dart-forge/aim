@Tags(['integration'])
library;

import 'dart:async';

import 'package:aim_mysql/aim_mysql.dart';
import 'package:rig_mysql/rig_mysql.dart';
import 'package:test/test.dart';

void main() {
  final lease = useMySql();
  late MySqlDatabase db;

  setUp(() async {
    db = await MySqlDatabase.connect(
      '${lease.url}?sslmode=disable&allowPublicKeyRetrieval=true',
    );
  });

  tearDown(() => db.close());

  test('a duplicate key is a unique violation', () async {
    await db.execute('CREATE TABLE uniq (id INT PRIMARY KEY)');
    await db.execute('INSERT INTO uniq VALUES (1)');

    // Also the execute-time sql-threading site: unlike a prepare-time
    // failure (syntax error, unknown table), this one only fails once the
    // statement actually runs.
    await expectLater(
      db.execute('INSERT INTO uniq VALUES (1)'),
      throwsA(
        isA<MySqlUniqueViolation>()
            .having((e) => e.errorCode, 'errno', 1062)
            .having((e) => e.sql, 'sql', contains('INSERT INTO uniq')),
      ),
    );
  });

  test('a null in a NOT NULL column is a NOT NULL violation', () async {
    await db.execute('CREATE TABLE notnull_t (a INT NOT NULL)');

    await expectLater(
      db.execute('INSERT INTO notnull_t VALUES (NULL)'),
      throwsA(isA<MySqlNotNullViolation>()),
    );
  });

  test('a missing parent row is a foreign key violation', () async {
    await db.execute(
      'CREATE TABLE parent (id INT PRIMARY KEY) ENGINE = InnoDB',
    );
    await db.execute('''
      CREATE TABLE child (
        id INT PRIMARY KEY,
        parent_id INT,
        FOREIGN KEY (parent_id) REFERENCES parent(id)
      ) ENGINE = InnoDB
    ''');

    await expectLater(
      db.execute('INSERT INTO child VALUES (1, 99)'),
      throwsA(isA<MySqlForeignKeyViolation>()),
    );
  });

  test('deleting a referenced row is a foreign key violation too', () async {
    await db.execute('CREATE TABLE p2 (id INT PRIMARY KEY) ENGINE = InnoDB');
    await db.execute('''
      CREATE TABLE c2 (
        id INT PRIMARY KEY,
        p INT,
        FOREIGN KEY (p) REFERENCES p2(id)
      ) ENGINE = InnoDB
    ''');
    await db.execute('INSERT INTO p2 VALUES (1)');
    await db.execute('INSERT INTO c2 VALUES (1, 1)');

    await expectLater(
      db.execute('DELETE FROM p2 WHERE id = 1'),
      throwsA(isA<MySqlForeignKeyViolation>()),
    );
  });

  test('a failed CHECK is a check violation', () async {
    // 3819, and the reason the parser has to read both bytes of the errno.
    await db.execute('CREATE TABLE checked (a INT CHECK (a > 0))');

    await expectLater(
      db.execute('INSERT INTO checked VALUES (-1)'),
      throwsA(
        isA<MySqlCheckViolation>().having((e) => e.errorCode, 'errno', 3819),
      ),
    );
  });

  test('a lock wait timeout is its own type', () async {
    // Distinct from a deadlock because retrying immediately is right for a
    // deadlock and usually wrong for this.
    await db.execute(
      'CREATE TABLE locked (id INT PRIMARY KEY) ENGINE = InnoDB',
    );
    await db.execute('INSERT INTO locked VALUES (1)');

    final other = await MySqlDatabase.connect(
      '${lease.url}?sslmode=disable&allowPublicKeyRetrieval=true',
    );
    addTearDown(other.close);

    // The completer is what makes this deterministic: without it the second
    // transaction can ask for the row before the first has taken it, and
    // the test passes or fails on timing.
    final holdsTheLock = Completer<void>();
    final releaseTheLock = Completer<void>();
    final holding = other.transaction((tx) async {
      await tx.execute('SELECT * FROM locked WHERE id = 1 FOR UPDATE');
      holdsTheLock.complete();
      await releaseTheLock.future;
    });

    await holdsTheLock.future;

    await expectLater(
      db.transaction((tx) async {
        // Set inside the transaction, not outside: outside, the pool can
        // hand the SET and the SELECT to different connections and the
        // setting would apply to neither of the ones that matter.
        await tx.execute('SET SESSION innodb_lock_wait_timeout = 1');
        await tx.execute('SELECT * FROM locked WHERE id = 1 FOR UPDATE');
      }),
      throwsA(isA<MySqlLockWaitTimeout>()),
    );

    releaseTheLock.complete();
    await holding;
  });

  test(
    'an unknown table is a plain MySqlException carrying its errno',
    () async {
      // Not classified, not swallowed: the caller can branch on 1146 itself.
      await expectLater(
        db.query('SELECT * FROM no_such_table'),
        throwsA(
          isA<MySqlException>().having((e) => e.errorCode, 'errno', 1146),
        ),
      );
    },
  );

  test('a syntax error carries 1064', () async {
    await expectLater(
      db.query('SELCT 1'),
      throwsA(isA<MySqlException>().having((e) => e.errorCode, 'errno', 1064)),
    );
  });

  test('a failed statement is in the exception', () async {
    // So a log line says which query failed without the caller adding it.
    await expectLater(
      db.query('SELECT * FROM no_such_table'),
      throwsA(
        isA<MySqlException>().having(
          (e) => e.sql,
          'sql',
          contains('no_such_table'),
        ),
      ),
    );
  });

  test(
    'a statement that fails partway through its rows carries the sql too',
    () async {
      // Different from the two cases above: the reply already committed to
      // a row shape (the header and, here, two real rows) before the
      // BIGINT UNSIGNED underflow on the third row turns it into an error.
      // That is a separate place in the driver that has to attach sql.
      await db.execute(
        'CREATE TABLE midstream (id INT PRIMARY KEY, n BIGINT UNSIGNED)',
      );
      await db.execute('INSERT INTO midstream VALUES (1, 5), (2, 3), (3, 1)');

      await expectLater(
        db.query('SELECT id, n - 2 FROM midstream ORDER BY id'),
        throwsA(
          isA<MySqlException>()
              .having((e) => e.errorCode, 'errno', 1690)
              .having((e) => e.sql, 'sql', contains('midstream')),
        ),
      );
    },
  );

  test('a deadlock is its own type', () async {
    await db.execute(
      'CREATE TABLE crossed (id INT PRIMARY KEY) ENGINE = InnoDB',
    );
    await db.execute('INSERT INTO crossed VALUES (1), (2)');

    final other = await MySqlDatabase.connect(
      '${lease.url}?sslmode=disable&allowPublicKeyRetrieval=true',
    );
    addTearDown(other.close);

    final hasFirst = Completer<void>();
    final hasSecond = Completer<void>();

    // Each transaction takes one row, waits for the other to have taken
    // its own, and only then reaches across. The completers are what make
    // the cycle certain rather than likely.
    Future<void> takeThenCross(
      MySqlDatabase on,
      int mine,
      int theirs,
      Completer<void> announce,
      Future<void> theirTurn,
    ) => on.transaction((tx) async {
      await tx.query(
        'SELECT * FROM crossed WHERE id = ? FOR UPDATE',
        args: [mine],
      );
      announce.complete();
      await theirTurn;
      await tx.query(
        'SELECT * FROM crossed WHERE id = ? FOR UPDATE',
        args: [theirs],
      );
    });

    final errors = <Object>[];
    await Future.wait([
      takeThenCross(
        db,
        1,
        2,
        hasFirst,
        hasSecond.future,
      ).catchError((Object e) => errors.add(e)),
      takeThenCross(
        other,
        2,
        1,
        hasSecond,
        hasFirst.future,
      ).catchError((Object e) => errors.add(e)),
    ]);

    // InnoDB picks the victim; we only claim that exactly one lost and
    // that it lost for this reason.
    expect(errors, hasLength(1));
    expect(errors.single, isA<MySqlDeadlock>());

    // And both databases still work. The server rolled the victim's
    // transaction back itself, so the driver's own ROLLBACK went to a
    // connection with no transaction open -- that must not leave either
    // side out of step.
    expect((await db.query('SELECT 1 AS a')).single['a'], 1);
    expect((await other.query('SELECT 1 AS a')).single['a'], 1);
  });
}
