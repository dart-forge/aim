@Tags(['integration'])
library;

import 'package:aim_postgres/src/pg_database.dart';
import 'package:test/test.dart';

void main() {
  late PostgresDatabase db;

  setUpAll(() async {
    // Docker Composeでテスト用PostgreSQLが起動していることを前提
    db = await PostgresDatabase.connect(
      'postgresql://test:test@localhost:15433/test_db',
    );

    // テスト用テーブル作成
    await db.query('''
      CREATE TABLE IF NOT EXISTS test_accounts (
        id SERIAL PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        balance DECIMAL(10, 2) NOT NULL DEFAULT 0
      )
    ''');
  });

  tearDownAll(() async {
    await db.query('DROP TABLE IF EXISTS test_accounts');
    await db.close();
  });

  setUp(() async {
    // 各テスト前にデータをクリーンアップ
    await db.query('DELETE FROM test_accounts');
  });

  group('Transaction - Commit', () {
    test('should commit transaction when no errors occur', () async {
      // トランザクション実行
      await db.transaction((tx) async {
        await tx.execute(
          'INSERT INTO test_accounts (name, balance) VALUES (\$1, \$2)',
          args: ['Alice', 1000.0],
        );
        await tx.execute(
          'INSERT INTO test_accounts (name, balance) VALUES (\$1, \$2)',
          args: ['Bob', 2000.0],
        );
      });

      // トランザクション後にデータが確定されていることを確認
      final accounts = await db.query('SELECT * FROM test_accounts ORDER BY name');
      expect(accounts.length, 2);
      expect(accounts[0]['name'], 'Alice');
      expect(accounts[0]['balance'], '1000.00');
      expect(accounts[1]['name'], 'Bob');
      expect(accounts[1]['balance'], '2000.00');
    });

    test('should support query within transaction', () async {
      // 初期データ投入
      await db.execute(
        'INSERT INTO test_accounts (name, balance) VALUES (\$1, \$2)',
        args: ['Charlie', 500.0],
      );

      String? queriedName;
      await db.transaction((tx) async {
        // トランザクション内でquery
        final result = await tx.query(
          'SELECT name FROM test_accounts WHERE name = \$1',
          args: ['Charlie'],
        );
        queriedName = result.first['name'] as String;

        // 新しいデータを追加
        await tx.execute(
          'INSERT INTO test_accounts (name, balance) VALUES (\$1, \$2)',
          args: ['David', 750.0],
        );
      });

      expect(queriedName, 'Charlie');

      // トランザクション後に両方のデータが存在することを確認
      final accounts = await db.query('SELECT * FROM test_accounts ORDER BY name');
      expect(accounts.length, 2);
      expect(accounts[0]['name'], 'Charlie');
      expect(accounts[1]['name'], 'David');
    });

    test('should support named parameters within transaction', () async {
      await db.transaction((tx) async {
        await tx.execute(
          'INSERT INTO test_accounts (name, balance) VALUES (\$1, \$2)',
          args: ['Eve', 1500.0],
        );

        // 名前付きパラメータでquery
        final result = await tx.query(
          'SELECT * FROM test_accounts WHERE name = :name',
          params: {'name': 'Eve'},
        );
        expect(result.length, 1);
        expect(result.first['name'], 'Eve');
      });

      // トランザクション後にデータが確定されていることを確認
      final accounts = await db.query('SELECT * FROM test_accounts');
      expect(accounts.length, 1);
    });

    test('should handle multiple operations in transaction', () async {
      await db.transaction((tx) async {
        // INSERT
        await tx.execute(
          'INSERT INTO test_accounts (name, balance) VALUES (\$1, \$2)',
          args: ['Frank', 3000.0],
        );

        // SELECT
        final inserted = await tx.query(
          'SELECT * FROM test_accounts WHERE name = \$1',
          args: ['Frank'],
        );
        expect(inserted.length, 1);

        // UPDATE
        await tx.execute(
          'UPDATE test_accounts SET balance = \$1 WHERE name = \$2',
          args: [3500.0, 'Frank'],
        );

        // 更新後のSELECT
        final updated = await tx.query(
          'SELECT balance FROM test_accounts WHERE name = \$1',
          args: ['Frank'],
        );
        expect(updated.first['balance'], '3500.00');
      });

      // トランザクション後に最終的なデータを確認
      final accounts = await db.query('SELECT * FROM test_accounts WHERE name = \$1', args: ['Frank']);
      expect(accounts.length, 1);
      expect(accounts.first['balance'], '3500.00');
    });
  });

  group('Transaction - Rollback', () {
    test('should rollback transaction when error occurs', () async {
      // 初期データ投入
      await db.execute(
        'INSERT INTO test_accounts (name, balance) VALUES (\$1, \$2)',
        args: ['Grace', 1000.0],
      );

      // エラーが発生するトランザクション
      try {
        await db.transaction((tx) async {
          await tx.execute(
            'INSERT INTO test_accounts (name, balance) VALUES (\$1, \$2)',
            args: ['Henry', 2000.0],
          );

          // エラーを発生させる
          throw Exception('Simulated error');
        });
      } catch (e) {
        expect(e.toString(), contains('Simulated error'));
      }

      // トランザクションがロールバックされ、Henryは追加されていないことを確認
      final accounts = await db.query('SELECT * FROM test_accounts ORDER BY name');
      expect(accounts.length, 1);
      expect(accounts[0]['name'], 'Grace');
    });

    test('should rollback on SQL error', () async {
      try {
        await db.transaction((tx) async {
          await tx.execute(
            'INSERT INTO test_accounts (name, balance) VALUES (\$1, \$2)',
            args: ['Ivy', 500.0],
          );

          // 不正なSQL（存在しないテーブル）
          await tx.execute('INSERT INTO non_existent_table (name) VALUES (\$1)', args: ['test']);
        });
        fail('Should have thrown an exception');
      } catch (e) {
        // PostgreSQLエラーが発生することを確認
        expect(e.toString(), isNotEmpty);
      }

      // トランザクションがロールバックされ、Ivyは追加されていないことを確認
      final accounts = await db.query('SELECT * FROM test_accounts');
      expect(accounts.length, 0);
    });

    test('should rollback when constraint violation occurs', () async {
      // 初期データ投入
      await db.execute(
        'INSERT INTO test_accounts (name, balance) VALUES (\$1, \$2)',
        args: ['Jack', 1000.0],
      );

      // JackのIDを取得
      final jackRecord = await db.query('SELECT id FROM test_accounts WHERE name = \$1', args: ['Jack']);
      final jackId = jackRecord.first['id'];

      // PRIMARY KEY違反を発生させる
      try {
        await db.transaction((tx) async {
          // Jackの残高を更新
          await tx.execute(
            'UPDATE test_accounts SET balance = \$1 WHERE name = \$2',
            args: [1500.0, 'Jack'],
          );

          // 新しいアカウントを追加
          await tx.execute(
            'INSERT INTO test_accounts (name, balance) VALUES (\$1, \$2)',
            args: ['Kate', 2000.0],
          );

          // 同じIDを持つレコードを無理やり挿入（エラー発生）
          await tx.execute(
            'INSERT INTO test_accounts (id, name, balance) VALUES (\$1, \$2, \$3)',
            args: [jackId, 'Duplicate', 3000.0],
          );
        });
        fail('Should have thrown an exception');
      } catch (e) {
        // 制約違反エラーが発生
        expect(e.toString(), isNotEmpty);
      }

      // トランザクション全体がロールバックされている
      final accounts = await db.query('SELECT * FROM test_accounts WHERE name = \$1', args: ['Jack']);
      expect(accounts.length, 1);
      // Jackの残高は元のまま（更新されていない）
      expect(accounts.first['balance'], '1000.00');

      // Kateも追加されていない
      final kate = await db.query('SELECT * FROM test_accounts WHERE name = \$1', args: ['Kate']);
      expect(kate.length, 0);
    });
  });

  group('Transaction - Real-world scenarios', () {
    test('should handle bank transfer correctly (commit)', () async {
      // 初期残高設定
      await db.execute(
        'INSERT INTO test_accounts (name, balance) VALUES (\$1, \$2)',
        args: ['Alice', 1000.0],
      );
      await db.execute(
        'INSERT INTO test_accounts (name, balance) VALUES (\$1, \$2)',
        args: ['Bob', 500.0],
      );

      // AliceからBobへ300円送金
      await db.transaction((tx) async {
        // Aliceの残高を減らす
        await tx.execute(
          'UPDATE test_accounts SET balance = balance - \$1 WHERE name = \$2',
          args: [300.0, 'Alice'],
        );

        // Bobの残高を増やす
        await tx.execute(
          'UPDATE test_accounts SET balance = balance + \$1 WHERE name = \$2',
          args: [300.0, 'Bob'],
        );
      });

      // 送金後の残高を確認
      final alice = await db.query('SELECT balance FROM test_accounts WHERE name = \$1', args: ['Alice']);
      expect(alice.first['balance'], '700.00');

      final bob = await db.query('SELECT balance FROM test_accounts WHERE name = \$1', args: ['Bob']);
      expect(bob.first['balance'], '800.00');
    });

    test('should handle bank transfer with insufficient funds (rollback)', () async {
      // 初期残高設定
      await db.execute(
        'INSERT INTO test_accounts (name, balance) VALUES (\$1, \$2)',
        args: ['Charlie', 100.0],
      );
      await db.execute(
        'INSERT INTO test_accounts (name, balance) VALUES (\$1, \$2)',
        args: ['David', 500.0],
      );

      // Charlieから500円送金しようとする（残高不足）
      try {
        await db.transaction((tx) async {
          // Charlieの残高を減らす
          await tx.execute(
            'UPDATE test_accounts SET balance = balance - \$1 WHERE name = \$2',
            args: [500.0, 'Charlie'],
          );

          // 残高確認
          final charlie = await tx.query(
            'SELECT balance FROM test_accounts WHERE name = \$1',
            args: ['Charlie'],
          );
          final balance = double.parse(charlie.first['balance'] as String);

          // 残高がマイナスになったらエラー
          if (balance < 0) {
            throw Exception('Insufficient funds');
          }

          // Davidの残高を増やす（ここまで到達しない）
          await tx.execute(
            'UPDATE test_accounts SET balance = balance + \$1 WHERE name = \$2',
            args: [500.0, 'David'],
          );
        });
        fail('Should have thrown an exception');
      } catch (e) {
        expect(e.toString(), contains('Insufficient funds'));
      }

      // トランザクションがロールバックされ、残高は元のまま
      final charlie = await db.query('SELECT balance FROM test_accounts WHERE name = \$1', args: ['Charlie']);
      expect(charlie.first['balance'], '100.00');

      final david = await db.query('SELECT balance FROM test_accounts WHERE name = \$1', args: ['David']);
      expect(david.first['balance'], '500.00');
    });
  });
}
