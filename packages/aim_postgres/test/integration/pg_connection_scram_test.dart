@Tags(['integration'])
library;

import 'package:aim_postgres/src/pg_connection.dart';
import 'package:rig_postgres/rig_postgres.dart';
import 'package:test/test.dart';

void main() {
  final pg = usePostgres(auth: PgAuth.scram);

  group('SCRAM-SHA-256 Authentication', () {
    late PostgresConnection conn;

    setUp(() async {
      conn = await PostgresConnection.connect(pg.url);
    });

    tearDown(() async {
      await conn.close();
    });

    test('connects successfully with SCRAM-SHA-256', () async {
      final result = await conn.sendSimpleQuery('SELECT 1 as num');
      expect(result.rows.length, 1);
      expect(result.rows[0][0], 1);
    });

    test('executes SELECT query', () async {
      final result = await conn.sendSimpleQuery(
        "SELECT 'hello' as greeting, 42 as answer",
      );
      expect(result.rows.length, 1);
      expect(result.rows[0][0], 'hello');
      expect(result.rows[0][1], 42);
    });

    test('executes CREATE TABLE', () async {
      await conn.sendSimpleQuery('DROP TABLE IF EXISTS scram_test');
      final result = await conn.sendSimpleQuery(
        'CREATE TABLE scram_test (id SERIAL PRIMARY KEY, name TEXT)',
      );
      expect(result.rows.length, 0);
    });

    test('executes INSERT and SELECT', () async {
      await conn.sendSimpleQuery('DROP TABLE IF EXISTS scram_test');
      await conn.sendSimpleQuery(
        'CREATE TABLE scram_test (id SERIAL PRIMARY KEY, name TEXT)',
      );

      await conn.sendSimpleQuery(
        "INSERT INTO scram_test (name) VALUES ('Alice')",
      );
      await conn.sendSimpleQuery(
        "INSERT INTO scram_test (name) VALUES ('Bob')",
      );

      final result = await conn.sendSimpleQuery(
        'SELECT * FROM scram_test ORDER BY id',
      );
      expect(result.rows.length, 2);
      expect(result.rows[0][1], 'Alice');
      expect(result.rows[1][1], 'Bob');
    });

    test('executes UPDATE', () async {
      await conn.sendSimpleQuery('DROP TABLE IF EXISTS scram_test');
      await conn.sendSimpleQuery(
        'CREATE TABLE scram_test (id SERIAL PRIMARY KEY, name TEXT)',
      );
      await conn.sendSimpleQuery(
        "INSERT INTO scram_test (name) VALUES ('Alice')",
      );

      await conn.sendSimpleQuery(
        "UPDATE scram_test SET name = 'Alice Updated' WHERE name = 'Alice'",
      );

      final result = await conn.sendSimpleQuery('SELECT name FROM scram_test');
      expect(result.rows.length, 1);
      expect(result.rows[0][0], 'Alice Updated');
    });

    test('executes DELETE', () async {
      await conn.sendSimpleQuery('DROP TABLE IF EXISTS scram_test');
      await conn.sendSimpleQuery(
        'CREATE TABLE scram_test (id SERIAL PRIMARY KEY, name TEXT)',
      );
      await conn.sendSimpleQuery(
        "INSERT INTO scram_test (name) VALUES ('Alice')",
      );
      await conn.sendSimpleQuery(
        "INSERT INTO scram_test (name) VALUES ('Bob')",
      );

      await conn.sendSimpleQuery("DELETE FROM scram_test WHERE name = 'Alice'");

      final result = await conn.sendSimpleQuery('SELECT name FROM scram_test');
      expect(result.rows.length, 1);
      expect(result.rows[0][0], 'Bob');
    });
  });

  group('SCRAM-SHA-256 Extended Query Protocol', () {
    late PostgresConnection conn;

    setUp(() async {
      conn = await PostgresConnection.connect(pg.url);
      await conn.sendSimpleQuery('DROP TABLE IF EXISTS scram_test_extended');
      await conn.sendSimpleQuery(
        'CREATE TABLE scram_test_extended (id SERIAL PRIMARY KEY, name TEXT, age INT)',
      );
    });

    tearDown(() async {
      await conn.close();
    });

    test('executes SELECT with parameters', () async {
      await conn.sendExtendedQuery(
        'INSERT INTO scram_test_extended (name, age) VALUES (\$1, \$2)',
        ['Alice', 30],
      );

      final result = await conn.sendExtendedQuery(
        'SELECT * FROM scram_test_extended WHERE name = \$1',
        ['Alice'],
      );

      expect(result.rows.length, 1);
      expect(result.rows[0][1], 'Alice');
      expect(result.rows[0][2], 30);
    });

    test('executes INSERT with parameters', () async {
      final result = await conn.sendExtendedQuery(
        'INSERT INTO scram_test_extended (name, age) VALUES (\$1, \$2) RETURNING id',
        ['Bob', 25],
      );

      expect(result.rows.length, 1);
      expect(result.rows[0][0] as int, greaterThan(0));
    });

    test('executes UPDATE with parameters', () async {
      await conn.sendExtendedQuery(
        'INSERT INTO scram_test_extended (name, age) VALUES (\$1, \$2)',
        ['Charlie', 35],
      );

      await conn.sendExtendedQuery(
        'UPDATE scram_test_extended SET age = \$1 WHERE name = \$2',
        [40, 'Charlie'],
      );

      final result = await conn.sendExtendedQuery(
        'SELECT age FROM scram_test_extended WHERE name = \$1',
        ['Charlie'],
      );

      expect(result.rows.length, 1);
      expect(result.rows[0][0], 40);
    });

    test('executes DELETE with parameters', () async {
      await conn.sendExtendedQuery(
        'INSERT INTO scram_test_extended (name, age) VALUES (\$1, \$2)',
        ['David', 28],
      );

      await conn.sendExtendedQuery(
        'DELETE FROM scram_test_extended WHERE name = \$1',
        ['David'],
      );

      final result = await conn.sendExtendedQuery(
        'SELECT * FROM scram_test_extended WHERE name = \$1',
        ['David'],
      );

      expect(result.rows.length, 0);
    });

    test('handles NULL values', () async {
      await conn.sendExtendedQuery(
        'INSERT INTO scram_test_extended (name, age) VALUES (\$1, \$2)',
        ['Eve', null],
      );

      final result = await conn.sendExtendedQuery(
        'SELECT name, age FROM scram_test_extended WHERE name = \$1',
        ['Eve'],
      );

      expect(result.rows.length, 1);
      expect(result.rows[0][0], 'Eve');
      expect(result.rows[0][1], null);
    });

    test('handles multiple parameters', () async {
      await conn.sendExtendedQuery(
        'INSERT INTO scram_test_extended (name, age) VALUES (\$1, \$2), (\$3, \$4)',
        ['Frank', 45, 'Grace', 50],
      );

      final result = await conn.sendSimpleQuery(
        'SELECT COUNT(*) FROM scram_test_extended',
      );

      expect(result.rows.length, 1);
      expect(result.rows[0][0] as int, 2);
    });
  });

  group('SCRAM-SHA-256 Error Handling', () {
    late PostgresConnection conn;

    setUp(() async {
      conn = await PostgresConnection.connect(pg.url);
    });

    tearDown(() async {
      await conn.close();
    });

    test('throws QueryException on syntax error', () async {
      expect(
        () => conn.sendSimpleQuery('INVALID SQL SYNTAX'),
        throwsA(isA<QueryException>()),
      );
    });

    test('throws QueryException on non-existent table', () async {
      expect(
        () => conn.sendSimpleQuery('SELECT * FROM non_existent_table'),
        throwsA(isA<QueryException>()),
      );
    });

    test('throws QueryException on constraint violation', () async {
      await conn.sendSimpleQuery('DROP TABLE IF EXISTS scram_test_constraint');
      await conn.sendSimpleQuery(
        'CREATE TABLE scram_test_constraint (id INT PRIMARY KEY)',
      );
      await conn.sendSimpleQuery(
        'INSERT INTO scram_test_constraint VALUES (1)',
      );

      expect(
        () => conn.sendSimpleQuery(
          'INSERT INTO scram_test_constraint VALUES (1)',
        ),
        throwsA(isA<QueryException>()),
      );
    });
  });

  group('SCRAM-SHA-256 Connection', () {
    test('can establish multiple connections', () async {
      final conn1 = await PostgresConnection.connect(pg.url);
      final conn2 = await PostgresConnection.connect(pg.url);

      final result1 = await conn1.sendSimpleQuery('SELECT 1');
      final result2 = await conn2.sendSimpleQuery('SELECT 2');

      expect(result1.rows[0][0], 1);
      expect(result2.rows[0][0], 2);

      await conn1.close();
      await conn2.close();
    });

    test('fails with wrong password', () async {
      expect(
        () => PostgresConnection.connect(
          'postgresql://test:wrong_password@${pg.host}:${pg.port}/${pg.database}',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('sends Terminate message on close', () async {
      final testConn = await PostgresConnection.connect(pg.url);

      // Execute a query to ensure connection is ready
      final result = await testConn.sendSimpleQuery('SELECT 1');
      expect(result.rows.length, 1);

      // Close should send Terminate message and complete successfully
      await expectLater(testConn.close(), completes);
    });
  });
}
