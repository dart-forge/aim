import 'package:aim_orm/aim_orm.dart';
import 'package:test/test.dart';

void main() {
  group('integer() - defaults', () {
    test('creates a non-nullable, non-primary-key, non-unique column with '
        'no default', () {
      final col = integer('id');
      expect(col.name, equals('id'));
      expect(col.isNullable, isFalse);
      expect(col.isPrimaryKey, isFalse);
      expect(col.isUnique, isFalse);
      expect(col.defaultValue, isNull);
    });
  });

  group('Column - primaryKey()', () {
    test(
      'marks a fresh column as primary key without touching other flags',
      () {
        final col = integer('id').primaryKey();
        expect(col.isPrimaryKey, isTrue);
        expect(col.isNullable, isFalse);
        expect(col.isUnique, isFalse);
      },
    );

    test('is idempotent when called twice', () {
      final col = integer('id').primaryKey().primaryKey();
      expect(col.isPrimaryKey, isTrue);
    });
  });

  group('Column - nullable()', () {
    test('marks a column as nullable', () {
      final col = varchar('bio', length: 500).nullable();
      expect(col.isNullable, isTrue);
    });

    test('is idempotent when called twice', () {
      final col = varchar('bio', length: 500).nullable().nullable();
      expect(col.isNullable, isTrue);
    });
  });

  group('Column - unique()', () {
    test('adds a unique constraint', () {
      final col = varchar('email', length: 255).unique();
      expect(col.isUnique, isTrue);
    });

    test('is idempotent when called twice', () {
      final col = varchar('email', length: 255).unique().unique();
      expect(col.isUnique, isTrue);
    });
  });

  group('Column - withDefault()', () {
    test('sets the default value', () {
      final col = integer('count').withDefault(0);
      expect(col.defaultValue, equals(0));
    });

    test('a later withDefault() call replaces the earlier one', () {
      final col = integer('count').withDefault(1).withDefault(2);
      expect(col.defaultValue, equals(2));
    });
  });

  group('Column - modifiers compose the same way regardless of call order', () {
    test('primaryKey -> unique -> nullable -> withDefault', () {
      final col = integer('id').primaryKey().unique().nullable().withDefault(5);
      expect(col.isPrimaryKey, isTrue);
      expect(col.isUnique, isTrue);
      expect(col.isNullable, isTrue);
      expect(col.defaultValue, equals(5));
    });

    test(
      'withDefault -> nullable -> unique -> primaryKey reaches the same state',
      () {
        final col = integer('id')
            .withDefault(5)
            .nullable()
            .unique()
            .primaryKey();
        expect(col.isPrimaryKey, isTrue);
        expect(col.isUnique, isTrue);
        expect(col.isNullable, isTrue);
        expect(col.defaultValue, equals(5));
      },
    );
  });

  group('Column - modifiers return a new instance', () {
    test('the receiver is left unmodified', () {
      final original = integer('id');
      final withPk = original.primaryKey();
      expect(original.isPrimaryKey, isFalse);
      expect(withPk.isPrimaryKey, isTrue);
    });
  });

  group('IntegerColumn - toSql()', () {
    test('renders INTEGER', () {
      expect(integer('age').toSql(), equals('INTEGER'));
    });
  });

  group('VarcharColumn - toSql()', () {
    test('renders VARCHAR(length) with the given length', () {
      expect(varchar('name', length: 255).toSql(), equals('VARCHAR(255)'));
    });

    test('renders a different length correctly', () {
      expect(varchar('code', length: 10).toSql(), equals('VARCHAR(10)'));
    });

    // varchar() without a length is exercised by real code in this repo
    // (examples/orm-sample/lib/test.dart: `varchar('gender').nullable()`).
    // With no length given, VARCHAR has no length limit, so it must render
    // with no parentheses and never invent a default length.
    test('renders VARCHAR with no parentheses when no length is given', () {
      expect(varchar('gender').toSql(), equals('VARCHAR'));
    });

    test('a nullable column with no length still renders VARCHAR', () {
      expect(varchar('gender').nullable().toSql(), equals('VARCHAR'));
    });
  });

  group('TextColumn - toSql()', () {
    test('renders TEXT', () {
      expect(text('content').toSql(), equals('TEXT'));
    });
  });

  group('TimestampColumn - toSql()', () {
    test('renders TIMESTAMP', () {
      expect(timestamp('created_at').toSql(), equals('TIMESTAMP'));
    });
  });

  group('TimestampColumn - withDefaultNow()', () {
    test('sets defaultNow and preserves previously set flags', () {
      final col = timestamp('created_at').primaryKey().withDefaultNow();
      expect(col.defaultNow, isTrue);
      expect(col.isPrimaryKey, isTrue);
    });

    test('defaultNow starts out false', () {
      expect(timestamp('created_at').defaultNow, isFalse);
    });
  });

  group('OnDeleteAction - SQL keyword mapping', () {
    test('cascade maps to CASCADE', () {
      expect(OnDeleteAction.cascade.sqlKeyword, equals('CASCADE'));
    });

    test('setNull maps to SET NULL', () {
      expect(OnDeleteAction.setNull.sqlKeyword, equals('SET NULL'));
    });

    test('restrict maps to RESTRICT', () {
      expect(OnDeleteAction.restrict.sqlKeyword, equals('RESTRICT'));
    });

    test('setDefault maps to SET DEFAULT', () {
      expect(OnDeleteAction.setDefault.sqlKeyword, equals('SET DEFAULT'));
    });
  });

  group('OnUpdateAction - SQL keyword mapping', () {
    test('cascade maps to CASCADE', () {
      expect(OnUpdateAction.cascade.sqlKeyword, equals('CASCADE'));
    });

    test('setNull maps to SET NULL', () {
      expect(OnUpdateAction.setNull.sqlKeyword, equals('SET NULL'));
    });

    test('restrict maps to RESTRICT', () {
      expect(OnUpdateAction.restrict.sqlKeyword, equals('RESTRICT'));
    });

    test('setDefault maps to SET DEFAULT', () {
      expect(OnUpdateAction.setDefault.sqlKeyword, equals('SET DEFAULT'));
    });
  });
}
