@Tags(['integration'])
library;

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
    await db.execute('DROP TABLE IF EXISTS accounts');
    // InnoDB, because MyISAM would silently ignore every rollback here.
    await db.execute('''
      CREATE TABLE accounts (
        id INT PRIMARY KEY,
        balance INT NOT NULL
      ) ENGINE = InnoDB
    ''');
    await db.execute('INSERT INTO accounts VALUES (1, 100), (2, 100)');
  });

  tearDown(() => db.close());

  Future<int> balanceOf(int id) async =>
      (await db.query(
            'SELECT balance FROM accounts WHERE id = :id',
            params: {'id': id},
          )).single['balance']
          as int;

  test('commits on success', () async {
    await db.transaction((tx) async {
      await tx.execute('UPDATE accounts SET balance = 90 WHERE id = 1');
      await tx.execute('UPDATE accounts SET balance = 110 WHERE id = 2');
    });

    expect(await balanceOf(1), 90);
    expect(await balanceOf(2), 110);
  });

  test('rolls back everything when the body throws', () async {
    await expectLater(
      db.transaction((tx) async {
        await tx.execute('UPDATE accounts SET balance = 0 WHERE id = 1');
        throw StateError('no');
      }),
      throwsA(isA<StateError>()),
    );

    expect(await balanceOf(1), 100);
  });

  test('rolls back when a statement fails', () async {
    await expectLater(
      db.transaction((tx) async {
        await tx.execute('UPDATE accounts SET balance = 0 WHERE id = 1');
        await tx.execute('INSERT INTO accounts VALUES (1, 0)');
      }),
      throwsA(isA<MySqlUniqueViolation>()),
    );

    expect(await balanceOf(1), 100);
  });

  test('the body sees its own uncommitted writes', () async {
    await db.transaction((tx) async {
      await tx.execute('UPDATE accounts SET balance = 7 WHERE id = 1');

      final rows = await tx.query('SELECT balance FROM accounts WHERE id = 1');

      expect(rows.single['balance'], 7);
    });
  });

  test('nothing outside sees them until it commits', () async {
    // Which also proves the transaction holds one connection rather than
    // taking a fresh one per statement.
    await db.transaction((tx) async {
      await tx.execute('UPDATE accounts SET balance = 7 WHERE id = 1');

      expect(await balanceOf(1), 100);
    });

    expect(await balanceOf(1), 7);
  });

  test("returns the body's value", () async {
    expect(await db.transaction((tx) async => 42), 42);
  });

  test('a transaction kept past transaction() refuses further use', () async {
    // Holding tx and calling it after the body has returned must not
    // reach the connection at all: by then it may already be back in
    // the pool, possibly handed to a completely different caller.
    late MySqlTransaction leaked;
    await db.transaction((tx) async {
      leaked = tx;
    });

    await expectLater(
      leaked.execute('UPDATE accounts SET balance = 0 WHERE id = 1'),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      leaked.query('SELECT balance FROM accounts WHERE id = 1'),
      throwsA(isA<StateError>()),
    );

    // And the UPDATE above never actually ran.
    expect(await balanceOf(1), 100);
  });

  test('insert works inside a transaction', () async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS auto (id INT AUTO_INCREMENT PRIMARY KEY, v INT)',
    );

    final id = await db.transaction(
      (tx) => tx.insert('INSERT INTO auto (v) VALUES (:v)', params: {'v': 1}),
    );

    expect(id, greaterThan(0));
  });

  group('DDL inside a transaction', () {
    test('is reported instead of silently committing', () async {
      // MySQL commits implicitly on DDL. Without this check the update
      // above it would be permanent and the rollback would do nothing,
      // with no sign that the transaction had ended.
      await expectLater(
        db.transaction((tx) async {
          await tx.execute('UPDATE accounts SET balance = 0 WHERE id = 1');
          await tx.execute('CREATE TABLE ddl_inside (a INT)');
          await tx.execute('UPDATE accounts SET balance = 1 WHERE id = 2');
        }),
        throwsA(isA<MySqlTransactionEndedByDdl>()),
      );
    });

    test('the failure names the statement that ended it', () async {
      await expectLater(
        db.transaction((tx) async {
          await tx.execute('CREATE TABLE ddl_named (a INT)');
        }),
        throwsA(
          isA<MySqlTransactionEndedByDdl>().having(
            (e) => e.toString(),
            'toString',
            allOf(contains('ddl_named'), contains('committed')),
          ),
        ),
      );
    });

    test('and it says so rather than pretending the rollback worked', () async {
      // The update before the DDL is committed and cannot be undone. The
      // test asserts the honest outcome, not the one we would prefer.
      await expectLater(
        db.transaction((tx) async {
          await tx.execute('UPDATE accounts SET balance = 55 WHERE id = 1');
          await tx.execute('CREATE TABLE ddl_kept (a INT)');
        }),
        throwsA(isA<MySqlTransactionEndedByDdl>()),
      );

      expect(
        await balanceOf(1),
        55,
        reason: 'the DDL committed it; nothing can roll it back',
      );
    });

    test('a DDL that fails still ends the transaction', () async {
      // MySQL's implicit commit fires before the statement completes, so
      // it fires even when the statement itself then fails -- here,
      // because the table already exists. An ERR packet carries no status
      // flags, so this can only be noticed with a follow-up probe. The
      // honest assertion is that the earlier write is still committed, the
      // same as when the ending statement succeeds -- not that a failed
      // statement somehow left the rollback able to undo it.
      await db.execute('CREATE TABLE already_there (a INT)');

      await expectLater(
        db.transaction((tx) async {
          await tx.execute('UPDATE accounts SET balance = 42 WHERE id = 1');
          await tx.execute('CREATE TABLE already_there (a INT)');
        }),
        throwsA(
          // Unlike a successful DDL, this path only knows the transaction
          // is gone -- not whether the work before it was committed or
          // rolled back. Some errno that ends a transaction this way
          // (ER_LOCK_TABLE_FULL, 1206) has no dedicated exception type, so
          // a type-based exclusion can never cover every such case; the
          // message must not claim "committed" the way the success-path
          // message does.
          isA<MySqlTransactionEndedByDdl>().having(
            (e) => e.toString(),
            'toString',
            contains('cannot tell'),
          ),
        ),
      );

      expect(
        await balanceOf(1),
        42,
        reason: 'the failed CREATE TABLE still committed it implicitly',
      );
    });
  });
}
