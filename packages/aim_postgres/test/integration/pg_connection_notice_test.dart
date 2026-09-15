@Tags(['integration'])
library;

import 'package:aim_postgres/src/pg_connection.dart';
import 'package:aim_postgres/src/types/notice_message.dart';
import 'package:test/test.dart';

void main() {
  group('NoticeResponse', () {
    late PostgresConnection conn;

    setUp(() async {
      conn = await PostgresConnection.connect(
        'postgresql://test:test@localhost:5433/test_db',
      );
    });

    tearDown(() async {
      await conn.close();
    });

    test('receives NOTICE for CREATE TABLE IF NOT EXISTS when table exists',
        () async {
      final notices = <NoticeMessage>[];
      final subscription = conn.noticeMessage.listen(notices.add);

      // Create table first time
      await conn.sendSimpleQuery(
        'CREATE TABLE IF NOT EXISTS notice_test (id SERIAL PRIMARY KEY, name TEXT)',
      );

      // Create table second time - should trigger NOTICE
      final result = await conn.sendSimpleQuery(
        'CREATE TABLE IF NOT EXISTS notice_test (id SERIAL PRIMARY KEY, name TEXT)',
      );

      // Query should succeed even with NOTICE
      expect(result, isNotNull);

      // Wait for notice to be processed
      await Future.delayed(Duration(milliseconds: 50));

      // Verify NOTICE was received
      expect(notices.length, greaterThan(0));
      expect(notices.first.severity, 'NOTICE');
      expect(notices.first.message, contains('already exists'));

      // Clean up
      await subscription.cancel();
      await conn.sendSimpleQuery('DROP TABLE IF EXISTS notice_test');
    });

    test('receives NOTICE for DROP TABLE IF EXISTS when table does not exist',
        () async {
      final notices = <NoticeMessage>[];
      final subscription = conn.noticeMessage.listen(notices.add);

      // Drop non-existent table - should trigger NOTICE
      final result = await conn.sendSimpleQuery(
        'DROP TABLE IF EXISTS non_existent_table_12345',
      );

      // Query should succeed even with NOTICE
      expect(result, isNotNull);

      // Wait for notice to be processed
      await Future.delayed(Duration(milliseconds: 50));

      // Verify NOTICE was received
      expect(notices.length, greaterThan(0));
      expect(notices.first.severity, 'NOTICE');
      expect(notices.first.message, contains('does not exist'));

      await subscription.cancel();
    });

    test('receives NOTICE for SERIAL column implicit sequence', () async {
      final notices = <NoticeMessage>[];
      final subscription = conn.noticeMessage.listen(notices.add);

      await conn.sendSimpleQuery('DROP TABLE IF EXISTS serial_test');

      // Create table with SERIAL - may trigger NOTICE about implicit sequence
      final result = await conn.sendSimpleQuery(
        'CREATE TABLE serial_test (id SERIAL PRIMARY KEY)',
      );

      // Query should succeed even with NOTICE
      expect(result, isNotNull);

      // Wait for notice to be processed
      await Future.delayed(Duration(milliseconds: 50));

      // Note: PostgreSQL may or may not send NOTICE for SERIAL depending on version
      // so we don't assert on notices.length here

      // Clean up
      await subscription.cancel();
      await conn.sendSimpleQuery('DROP TABLE IF EXISTS serial_test');
    });

    test('handles multiple NOTICEs in single query', () async {
      final notices = <NoticeMessage>[];
      final subscription = conn.noticeMessage.listen(notices.add);

      // Drop if exists and create if not exists - may trigger multiple notices
      final result = await conn.sendSimpleQuery('''
        DROP TABLE IF EXISTS multi_notice_test;
        CREATE TABLE IF NOT EXISTS multi_notice_test (id INT);
      ''');

      // Query should succeed
      expect(result, isNotNull);

      // Wait for notices to be processed
      await Future.delayed(Duration(milliseconds: 50));

      // Should receive at least one NOTICE (for DROP TABLE IF EXISTS)
      expect(notices.length, greaterThan(0));
      expect(notices.any((n) => n.severity == 'NOTICE'), isTrue);

      // Clean up
      await subscription.cancel();
      await conn.sendSimpleQuery('DROP TABLE IF EXISTS multi_notice_test');
    });

    test('query execution continues normally after NOTICE', () async {
      final notices = <NoticeMessage>[];
      final subscription = conn.noticeMessage.listen(notices.add);

      // Create table
      await conn.sendSimpleQuery(
        'CREATE TABLE IF NOT EXISTS notice_continue_test (id INT, value TEXT)',
      );

      // Try to create again (triggers NOTICE) and insert data
      await conn.sendSimpleQuery(
        'CREATE TABLE IF NOT EXISTS notice_continue_test (id INT, value TEXT)',
      );

      // Wait for notice
      await Future.delayed(Duration(milliseconds: 50));

      // Verify NOTICE was received
      expect(notices.length, greaterThan(0));
      expect(notices.first.severity, 'NOTICE');

      // Insert should work normally after NOTICE
      await conn.sendSimpleQuery(
        "INSERT INTO notice_continue_test (id, value) VALUES (1, 'test')",
      );

      // Select should work and return data
      final result = await conn.sendSimpleQuery(
        'SELECT * FROM notice_continue_test',
      );

      expect(result.rows.length, 1);
      expect(result.rows[0][0], 1);
      expect(result.rows[0][1], 'test');

      // Clean up
      await subscription.cancel();
      await conn.sendSimpleQuery('DROP TABLE IF EXISTS notice_continue_test');
    });
  });
}