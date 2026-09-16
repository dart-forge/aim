import 'package:aim_orm/aim_orm.dart';
import 'package:test/test.dart';

void main() {
  group('ConditionOperator - SQL keyword mapping', () {
    test('equal maps to =', () {
      expect(ConditionOperator.equal.operator, equals('='));
    });

    test('greaterThan maps to >', () {
      expect(ConditionOperator.greaterThan.operator, equals('>'));
    });

    test('lessThan maps to <', () {
      expect(ConditionOperator.lessThan.operator, equals('<'));
    });

    test('greaterThanOrEqual maps to >=', () {
      expect(ConditionOperator.greaterThanOrEqual.operator, equals('>='));
    });

    test('lessThanOrEqual maps to <=', () {
      expect(ConditionOperator.lessThanOrEqual.operator, equals('<='));
    });

    test('inList maps to IN', () {
      expect(ConditionOperator.inList.operator, equals('IN'));
    });
  });

  group('Condition.toSql() - comparison operators', () {
    test('equal renders "column = :column_paramIndex"', () {
      final condition = Condition('age', ConditionOperator.equal, 18);
      expect(condition.toSql(0), equals('age = :age_0'));
    });

    test('greaterThan renders "column > :column_paramIndex"', () {
      final condition = Condition('age', ConditionOperator.greaterThan, 18);
      expect(condition.toSql(0), equals('age > :age_0'));
    });

    test('lessThan renders "column < :column_paramIndex"', () {
      final condition = Condition('age', ConditionOperator.lessThan, 18);
      expect(condition.toSql(0), equals('age < :age_0'));
    });

    test('greaterThanOrEqual renders "column >= :column_paramIndex"', () {
      final condition = Condition(
        'age',
        ConditionOperator.greaterThanOrEqual,
        18,
      );
      expect(condition.toSql(0), equals('age >= :age_0'));
    });

    test('lessThanOrEqual renders "column <= :column_paramIndex"', () {
      final condition = Condition('age', ConditionOperator.lessThanOrEqual, 18);
      expect(condition.toSql(0), equals('age <= :age_0'));
    });
  });

  group('Condition.toSql() - inList', () {
    test('renders the placeholder wrapped in parentheses', () {
      final condition = Condition('id', ConditionOperator.inList, [1, 2, 3]);
      expect(condition.toSql(0), equals('id IN (:id_0)'));
    });
  });

  group('Condition.toSql() - paramIndex numbering', () {
    test('the placeholder suffix tracks the given paramIndex', () {
      final condition = Condition('age', ConditionOperator.equal, 18);
      expect(condition.toSql(0), equals('age = :age_0'));
      expect(condition.toSql(1), equals('age = :age_1'));
      expect(condition.toSql(7), equals('age = :age_7'));
    });

    test('two conditions at consecutive indices get distinct placeholders '
        '(as when a WHERE clause combines several conditions)', () {
      final first = Condition('name', ConditionOperator.equal, 'Alice');
      final second = Condition(
        'email',
        ConditionOperator.equal,
        'alice@example.com',
      );
      expect(first.toSql(0), equals('name = :name_0'));
      expect(second.toSql(1), equals('email = :email_1'));
    });

    test('the same column name at different indices does not collide '
        '(the reason toSql takes a paramIndex at all)', () {
      final first = Condition('age', ConditionOperator.greaterThanOrEqual, 18);
      final second = Condition('age', ConditionOperator.lessThanOrEqual, 65);
      expect(first.toSql(0), equals('age >= :age_0'));
      expect(second.toSql(1), equals('age <= :age_1'));
    });
  });

  group('Condition.toParams()', () {
    test('keys the value by "<column>_<paramIndex>"', () {
      final condition = Condition('age', ConditionOperator.equal, 18);
      expect(condition.toParams(0), equals({'age_0': 18}));
    });

    test('paramIndex changes the key', () {
      final condition = Condition('age', ConditionOperator.equal, 18);
      expect(condition.toParams(3), equals({'age_3': 18}));
    });

    test('inList keeps the whole list as a single parameter value', () {
      final condition = Condition('id', ConditionOperator.inList, [1, 2, 3]);
      expect(
        condition.toParams(0),
        equals({
          'id_0': [1, 2, 3],
        }),
      );
    });
  });

  group(
    'Condition - toSql() and toParams() name the placeholder consistently',
    () {
      test(
        'for every operator, the placeholder in toSql matches the toParams key',
        () {
          for (final operator in ConditionOperator.values) {
            final value = operator == ConditionOperator.inList ? [1, 2] : 1;
            final condition = Condition('col', operator, value);

            final sql = condition.toSql(2);
            final params = condition.toParams(2);
            final paramName = params.keys.single;

            expect(
              sql,
              contains(':$paramName'),
              reason: 'operator: $operator, sql: $sql, params: $params',
            );
          }
        },
      );
    },
  );

  group('Column - operator methods build the matching Condition', () {
    test('eq', () {
      final condition = integer('age').eq(18);
      expect(condition.column, equals('age'));
      expect(condition.operator, equals(ConditionOperator.equal));
      expect(condition.value, equals(18));
    });

    test('gt', () {
      final condition = integer('age').gt(18);
      expect(condition.operator, equals(ConditionOperator.greaterThan));
      expect(condition.value, equals(18));
    });

    test('lt', () {
      final condition = integer('age').lt(18);
      expect(condition.operator, equals(ConditionOperator.lessThan));
      expect(condition.value, equals(18));
    });

    test('gte', () {
      final condition = integer('age').gte(18);
      expect(condition.operator, equals(ConditionOperator.greaterThanOrEqual));
      expect(condition.value, equals(18));
    });

    test('lte', () {
      final condition = integer('age').lte(18);
      expect(condition.operator, equals(ConditionOperator.lessThanOrEqual));
      expect(condition.value, equals(18));
    });

    test('inList', () {
      final condition = integer('id').inList([1, 2, 3]);
      expect(condition.operator, equals(ConditionOperator.inList));
      expect(condition.value, equals([1, 2, 3]));
    });

    test(
      'the condition carries the column\'s own name, not the Dart field name',
      () {
        final condition = varchar('user_name', length: 100).eq('Alice');
        expect(condition.column, equals('user_name'));
      },
    );
  });
}
