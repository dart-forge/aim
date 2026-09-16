import 'package:aim_orm_postgres/aim_orm_postgres.dart';
import 'package:test/test.dart';

void main() {
  group('SerialColumn - toSql()', () {
    test('renders SERIAL', () {
      expect(serial('id').toSql(), equals('SERIAL'));
    });

    test('renders SERIAL regardless of primaryKey/unique/nullable', () {
      expect(
        serial('id').primaryKey().unique().nullable().toSql(),
        equals('SERIAL'),
      );
    });
  });

  group('UuidColumn - toSql()', () {
    test('renders UUID', () {
      expect(uuid('id').toSql(), equals('UUID'));
    });

    test('renders UUID regardless of primaryKey/unique/nullable/default', () {
      expect(
        uuid('id')
            .primaryKey()
            .unique()
            .nullable()
            .withDefault('00000000-0000-0000-0000-000000000000')
            .toSql(),
        equals('UUID'),
      );
    });
  });

  group('JsonbColumn<T> - toSql()', () {
    test('renders JSONB for a Map type parameter', () {
      expect(jsonb<Map<String, dynamic>>('metadata').toSql(), equals('JSONB'));
    });

    test('renders JSONB for a List type parameter', () {
      expect(jsonb<List<String>>('tags').toSql(), equals('JSONB'));
    });

    test('renders JSONB regardless of primaryKey/unique/nullable/default', () {
      expect(
        jsonb<Map<String, dynamic>>('metadata')
            .primaryKey()
            .unique()
            .nullable()
            .withDefault({'a': 1})
            .toSql(),
        equals('JSONB'),
      );
    });
  });

  // None of SerialColumn, UuidColumn or JsonbColumn accept a length or
  // precision option -- the PostgreSQL types they represent (SERIAL, UUID,
  // JSONB) don't take one, unlike VarcharColumn in aim_orm. So there is no
  // "renders with/without length" case to cover here the way there is for
  // VARCHAR.
}
