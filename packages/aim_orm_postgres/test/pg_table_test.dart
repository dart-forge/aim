import 'package:aim_orm/aim_orm.dart';
import 'package:aim_orm_postgres/aim_orm_postgres.dart';
import 'package:test/test.dart';

void main() {
  group('PgTable', () {
    test('exposes the table name it was given', () {
      expect(const PgTable('users').name, equals('users'));
    });

    test('is a Table', () {
      expect(const PgTable('users'), isA<Table>());
    });

    test('different annotations expose different names', () {
      expect(const PgTable('users').name, equals('users'));
      expect(const PgTable('posts').name, equals('posts'));
    });
  });
}
