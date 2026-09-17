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

    // SerialColumn.copyWith() accepts a `defaultValue` argument (the
    // Column<T, Self> contract requires the parameter) but never forwards
    // it to the SerialColumn constructor, which always passes
    // `defaultValue: null` to the super constructor. So
    // `serial('id').withDefault(x)` silently returns a column whose
    // defaultValue is still null -- withDefault() has no visible effect for
    // this type, and nothing reports that the call did nothing. See the
    // report for details; that behaviour is deliberately left untested
    // here rather than asserted as correct.
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
