import 'package:aim_postgres/src/pg_connection.dart';
import 'package:aim_postgres/src/pg_database.dart';
import 'package:test/test.dart';

void main() {
  late PostgresDatabase db;

  setUpAll(() async {
    // Docker Composeでテスト用PostgreSQLが起動していることを前提
    db = await PostgresDatabase.connect(
      'postgresql://test:test@localhost:5433/test_db',
    );

    // テスト用テーブル作成
    await db.query('''
      CREATE TABLE IF NOT EXISTS test_products (
        id SERIAL PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        price DECIMAL(10, 2),
        in_stock BOOLEAN DEFAULT true
      )
    ''');

    // テストデータ投入
    await db.query('''
      INSERT INTO test_products (name, price, in_stock) VALUES
        ('Laptop', 999.99, true),
        ('Mouse', 29.99, true),
        ('Keyboard', 79.99, false)
    ''');
  });

  tearDownAll(() async {
    await db.query('DROP TABLE IF EXISTS test_products');
    await db.close();
  });

  group('Query with no parameters (Simple Query)', () {
    test('SELECT all products', () async {
      final products = await db.query('SELECT * FROM test_products ORDER BY id');

      expect(products.length, 3);
      expect(products[0]['name'], 'Laptop');
      expect(products[1]['name'], 'Mouse');
      expect(products[2]['name'], 'Keyboard');
    });

    test('SELECT with WHERE clause (no params)', () async {
      final products =
          await db.query("SELECT * FROM test_products WHERE name = 'Mouse'");

      expect(products.length, 1);
      expect(products[0]['name'], 'Mouse');
      expect(products[0]['price'], '29.99');
    });
  });

  group('Query with named parameters', () {
    test('SELECT with single named parameter', () async {
      final products = await db.query(
        'SELECT * FROM test_products WHERE name = :name',
        params: {'name': 'Laptop'},
      );

      expect(products.length, 1);
      expect(products[0]['name'], 'Laptop');
      expect(products[0]['price'], '999.99');
    });

    test('SELECT with multiple named parameters', () async {
      final products = await db.query(
        'SELECT * FROM test_products WHERE price > :min_price AND in_stock = :available',
        params: {'min_price': 50, 'available': true},
      );

      expect(products.length, 1);
      expect(products[0]['name'], 'Laptop');
    });

    test('INSERT with named parameters', () async {
      await db.query(
        'INSERT INTO test_products (name, price, in_stock) VALUES (:name, :price, :stock)',
        params: {'name': 'Monitor', 'price': 299.99, 'stock': true},
      );

      final products = await db.query(
        'SELECT * FROM test_products WHERE name = :name',
        params: {'name': 'Monitor'},
      );

      expect(products.length, 1);
      expect(products[0]['name'], 'Monitor');
      expect(products[0]['price'], '299.99');
    });

    test('UPDATE with named parameters', () async {
      await db.query(
        'UPDATE test_products SET price = :new_price WHERE name = :name',
        params: {'new_price': 999.99, 'name': 'Monitor'},
      );

      final products = await db.query(
        'SELECT price FROM test_products WHERE name = :name',
        params: {'name': 'Monitor'},
      );

      expect(products[0]['price'], '999.99');
    });

    test('DELETE with named parameters', () async {
      await db.query(
        'DELETE FROM test_products WHERE name = :name',
        params: {'name': 'Monitor'},
      );

      final products = await db.query(
        'SELECT * FROM test_products WHERE name = :name',
        params: {'name': 'Monitor'},
      );

      expect(products, isEmpty);
    });

    test('handles NULL in named parameters', () async {
      await db.query(
        'INSERT INTO test_products (name, price) VALUES (:name, :price)',
        params: {'name': 'NullPriceProduct', 'price': null},
      );

      final products = await db.query(
        'SELECT * FROM test_products WHERE name = :name',
        params: {'name': 'NullPriceProduct'},
      );

      expect(products[0]['price'], null);

      // クリーンアップ
      await db.query(
        'DELETE FROM test_products WHERE name = :name',
        params: {'name': 'NullPriceProduct'},
      );
    });
  });

  group('Query with positional parameters', () {
    test('SELECT with single positional parameter', () async {
      final products = await db.query(
        'SELECT * FROM test_products WHERE name = \$1',
        args: ['Mouse'],
      );

      expect(products.length, 1);
      expect(products[0]['name'], 'Mouse');
    });

    test('SELECT with multiple positional parameters', () async {
      final products = await db.query(
        'SELECT * FROM test_products WHERE price < \$1 AND in_stock = \$2',
        args: [100, true],
      );

      expect(products.length, 1);
      expect(products[0]['name'], 'Mouse');
    });

    test('INSERT with positional parameters', () async {
      await db.query(
        'INSERT INTO test_products (name, price, in_stock) VALUES (\$1, \$2, \$3)',
        args: ['Headphones', 149.99, true],
      );

      final products = await db.query(
        'SELECT * FROM test_products WHERE name = \$1',
        args: ['Headphones'],
      );

      expect(products.length, 1);
      expect(products[0]['name'], 'Headphones');
    });

    test('UPDATE with positional parameters', () async {
      await db.query(
        'UPDATE test_products SET in_stock = \$1 WHERE name = \$2',
        args: [false, 'Headphones'],
      );

      final products = await db.query(
        'SELECT in_stock FROM test_products WHERE name = \$1',
        args: ['Headphones'],
      );

      expect(products[0]['in_stock'], isFalse);
    });

    test('DELETE with positional parameters', () async {
      await db.query(
        'DELETE FROM test_products WHERE name = \$1',
        args: ['Headphones'],
      );

      final products = await db.query(
        'SELECT * FROM test_products WHERE name = \$1',
        args: ['Headphones'],
      );

      expect(products, isEmpty);
    });
  });

  group('Parameter validation', () {
    test('throws ArgumentError when both params and args provided', () async {
      expect(
        () => db.query(
          'SELECT * FROM test_products WHERE name = :name OR id = \$1',
          params: {'name': 'Laptop'},
          args: [1],
        ),
        throwsArgumentError,
      );
    });

    test('empty params map uses Simple Query', () async {
      final products = await db.query(
        'SELECT * FROM test_products',
        params: {},
      );
      expect(products.length, greaterThanOrEqualTo(3));
    });

    test('empty args list uses Simple Query', () async {
      final products = await db.query(
        'SELECT * FROM test_products',
        args: [],
      );
      expect(products.length, greaterThanOrEqualTo(3));
    });
  });

  group('Named parameter conversion', () {
    test('converts :param to \$1 correctly', () async {
      final products = await db.query(
        'SELECT * FROM test_products WHERE name = :product_name',
        params: {'product_name': 'Laptop'},
      );

      expect(products.length, 1);
      expect(products[0]['name'], 'Laptop');
    });

    test('converts multiple named params with correct indexing', () async {
      // :first -> $1, :second -> $2, :third -> $3
      final products = await db.query(
        'SELECT * FROM test_products WHERE price > :min AND price < :max AND in_stock = :available',
        params: {'min': 20, 'max': 100, 'available': true},
      );

      expect(products.length, 1);
      expect(products[0]['name'], 'Mouse');
    });

    test('handles repeated parameter names', () async {
      // :name appears twice, should be replaced with $1 both times
      final products = await db.query(
        'SELECT * FROM test_products WHERE name = :name OR name = :name',
        params: {'name': 'Laptop'},
      );

      expect(products.length, 1);
      expect(products[0]['name'], 'Laptop');
    });
  });

  group('Error handling', () {
    test('query throws QueryException on SQL error', () async {
      expect(
        () => db.query('SELCT * FROM test_products'), // typo
        throwsA(isA<QueryException>()),
      );
    });

    test('query with params throws QueryException on SQL error', () async {
      expect(
        () => db.query(
          'SELCT * FROM test_products WHERE id = :id',
          params: {'id': 1},
        ),
        throwsA(isA<QueryException>()),
      );
    });

    test('query with args throws QueryException on SQL error', () async {
      expect(
        () => db.query('SELCT * FROM test_products WHERE id = \$1', args: [1]),
        throwsA(isA<QueryException>()),
      );
    });
  });

  group('Execute method', () {
    test('execute INSERT with positional parameters', () async {
      final rowCount = await db.execute(
        'INSERT INTO test_products (name, price, in_stock) VALUES (\$1, \$2, \$3)',
        args: ['Webcam', 89.99, true],
      );

      expect(rowCount, 1);

      final products = await db.query(
        'SELECT * FROM test_products WHERE name = \$1',
        args: ['Webcam'],
      );
      expect(products.length, 1);
      expect(products[0]['name'], 'Webcam');
    });

    test('execute UPDATE with named parameters', () async {
      await db.execute(
        'INSERT INTO test_products (name, price) VALUES (\$1, \$2)',
        args: ['Speaker', 59.99],
      );

      final rowCount = await db.execute(
        'UPDATE test_products SET price = :price WHERE name = :name',
        params: {'price': 69.99, 'name': 'Speaker'},
      );

      expect(rowCount, 1);

      final products = await db.query(
        'SELECT price FROM test_products WHERE name = \$1',
        args: ['Speaker'],
      );
      expect(products[0]['price'], '69.99');
    });

    test('execute DELETE with positional parameters', () async {
      await db.execute(
        'INSERT INTO test_products (name, price) VALUES (\$1, \$2)',
        args: ['ToDelete', 9.99],
      );

      final rowCount = await db.execute(
        'DELETE FROM test_products WHERE name = \$1',
        args: ['ToDelete'],
      );

      expect(rowCount, 1);

      final products = await db.query(
        'SELECT * FROM test_products WHERE name = \$1',
        args: ['ToDelete'],
      );
      expect(products, isEmpty);
    });

    test('execute with no parameters', () async {
      final rowCount = await db.execute(
        "DELETE FROM test_products WHERE name = 'Webcam'",
      );

      expect(rowCount, 1);
    });

    test('execute throws ArgumentError when both params and args provided', () async {
      expect(
        () => db.execute(
          'UPDATE test_products SET price = :price WHERE id = \$1',
          params: {'price': 100},
          args: [1],
        ),
        throwsArgumentError,
      );
    });
  });
}
