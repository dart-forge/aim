import 'package:aim_orm/aim_orm.dart';
import 'package:aim_orm_postgres/aim_orm_postgres.dart';
import 'package:test/test.dart';

void main() {
  group('serial() - defaults', () {
    test('creates a non-nullable, non-primary-key, non-unique column with '
        'no default', () {
      final col = serial('id');
      expect(col.name, equals('id'));
      expect(col.isNullable, isFalse);
      expect(col.isPrimaryKey, isFalse);
      expect(col.isUnique, isFalse);
      expect(col.defaultValue, isNull);
    });

    test('returns a SerialColumn', () {
      expect(serial('id'), isA<SerialColumn>());
    });
  });

  group('SerialColumn - primaryKey() / unique() / nullable()', () {
    test('compose regardless of call order', () {
      final a = serial('id').primaryKey().unique().nullable();
      final b = serial('id').nullable().unique().primaryKey();
      for (final col in [a, b]) {
        expect(col.isPrimaryKey, isTrue);
        expect(col.isUnique, isTrue);
        expect(col.isNullable, isTrue);
      }
    });

    test('carries integer values, the type SERIAL stores', () {
      // The assignment is the assertion: it only compiles while the value
      // type is int. A serial column typed as text made every generated
      // comparison on a serial key take a string.
      final Column<int, SerialColumn> col = serial('id');
      expect(col.eq(1), isA<Condition>());
    });
  });

  group('SerialColumn - withDefault()', () {
    test('is refused, naming what the server would answer', () {
      expect(
        () => serial('id').withDefault(1),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('multiple default values'),
              contains('withDefault()'),
            ),
          ),
        ),
      );
    });

    test('is refused through copyWith as well', () {
      expect(
        () => serial('id').copyWith(defaultValue: 1),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('leaves the other modifiers working through copyWith', () {
      final col = serial('id').copyWith(isPrimaryKey: true);
      expect(col.isPrimaryKey, isTrue);
      expect(col.defaultValue, isNull);
    });
  });

  group('uuid() - defaults', () {
    test('creates a non-nullable, non-primary-key, non-unique column with '
        'no default', () {
      final col = uuid('id');
      expect(col.name, equals('id'));
      expect(col.isNullable, isFalse);
      expect(col.isPrimaryKey, isFalse);
      expect(col.isUnique, isFalse);
      expect(col.defaultValue, isNull);
    });

    test('returns a UuidColumn', () {
      expect(uuid('id'), isA<UuidColumn>());
    });
  });

  group('UuidColumn - modifiers compose regardless of call order', () {
    test('primaryKey -> unique -> nullable -> withDefault', () {
      final col = uuid('id')
          .primaryKey()
          .unique()
          .nullable()
          .withDefault('00000000-0000-0000-0000-000000000000');
      expect(col.isPrimaryKey, isTrue);
      expect(col.isUnique, isTrue);
      expect(col.isNullable, isTrue);
      expect(col.defaultValue, equals('00000000-0000-0000-0000-000000000000'));
    });

    test('withDefault -> nullable -> unique -> primaryKey reaches the '
        'same state', () {
      final col = uuid('id')
          .withDefault('00000000-0000-0000-0000-000000000000')
          .nullable()
          .unique()
          .primaryKey();
      expect(col.isPrimaryKey, isTrue);
      expect(col.isUnique, isTrue);
      expect(col.isNullable, isTrue);
      expect(col.defaultValue, equals('00000000-0000-0000-0000-000000000000'));
    });
  });

  group('jsonb<T>() - defaults', () {
    test('creates a non-nullable, non-primary-key, non-unique column with '
        'no default', () {
      final col = jsonb<Map<String, dynamic>>('metadata');
      expect(col.name, equals('metadata'));
      expect(col.isNullable, isFalse);
      expect(col.isPrimaryKey, isFalse);
      expect(col.isUnique, isFalse);
      expect(col.defaultValue, isNull);
    });

    test('returns a JsonbColumn<T> carrying the given type parameter', () {
      final col = jsonb<Map<String, dynamic>>('metadata');
      expect(col, isA<JsonbColumn<Map<String, dynamic>>>());
    });

    test('a different type parameter produces a different generic type', () {
      final col = jsonb<List<String>>('tags');
      expect(col, isA<JsonbColumn<List<String>>>());
      expect(col, isNot(isA<JsonbColumn<Map<String, dynamic>>>()));
    });
  });

  group('JsonbColumn<T> - modifiers compose regardless of call order', () {
    test('primaryKey -> unique -> nullable -> withDefault', () {
      final col = jsonb<Map<String, dynamic>>('metadata')
          .primaryKey()
          .unique()
          .nullable()
          .withDefault({'a': 1});
      expect(col.isPrimaryKey, isTrue);
      expect(col.isUnique, isTrue);
      expect(col.isNullable, isTrue);
      expect(col.defaultValue, equals({'a': 1}));
    });

    test('withDefault -> nullable -> unique -> primaryKey reaches the '
        'same state', () {
      final col = jsonb<Map<String, dynamic>>('metadata')
          .withDefault({'a': 1})
          .nullable()
          .unique()
          .primaryKey();
      expect(col.isPrimaryKey, isTrue);
      expect(col.isUnique, isTrue);
      expect(col.isNullable, isTrue);
      expect(col.defaultValue, equals({'a': 1}));
    });
  });
}
