import 'package:aim_database/aim_database.dart';
import 'package:aim_mysql/src/sql/placeholders.dart';
import 'package:test/test.dart';

void main() {
  (String, List<Object?>) rewrite(
    String sql,
    Map<String, Object?> params, {
    SqlDialect dialect = SqlDialect.mysql,
  }) => rewriteNamedParameters(sql, params, dialect: dialect);

  test('a single name becomes a question mark', () {
    final (sql, values) = rewrite('SELECT * FROM t WHERE id = :id', {'id': 1});
    expect(sql, 'SELECT * FROM t WHERE id = ?');
    expect(values, [1]);
  });

  test('values come out in the order the statement uses them', () {
    // Not in the order of the map: the server binds positionally.
    final (sql, values) = rewrite('SELECT * FROM t WHERE b = :b AND a = :a', {
      'a': 1,
      'b': 2,
    });
    expect(sql, 'SELECT * FROM t WHERE b = ? AND a = ?');
    expect(values, [2, 1]);
  });

  test('a name used twice is duplicated, because ? cannot be reused', () {
    // The whole difference from the Postgres driver, which points one $1
    // at both places.
    final (sql, values) = rewrite('SELECT * FROM t WHERE a = :x OR b = :x', {
      'x': 7,
    });
    expect(sql, 'SELECT * FROM t WHERE a = ? OR b = ?');
    expect(values, [7, 7]);
  });

  test('a name used three times appears three times', () {
    expect(rewrite('SELECT :x, :x, :x', {'x': 1}).$2, [1, 1, 1]);
  });

  test('a longer name is not eaten by a shorter one', () {
    // :user must not match the front of :user_id.
    final (sql, values) = rewrite('SELECT :user, :user_id', {
      'user': 'a',
      'user_id': 1,
    });
    expect(sql, 'SELECT ?, ?');
    expect(values, ['a', 1]);
  });

  test('a name inside a string literal is left alone', () {
    final (sql, values) = rewrite("SELECT ':id', :id", {'id': 1});
    expect(sql, "SELECT ':id', ?");
    expect(values, [1]);
  });

  test('a name inside a comment is left alone', () {
    final (sql, values) = rewrite('SELECT :id -- :other', {'id': 1});
    expect(sql, 'SELECT ? -- :other');
    expect(values, [1]);
  });

  test('a name inside a backquoted identifier is left alone', () {
    final (sql, values) = rewrite('SELECT `:id` FROM t WHERE x = :id', {
      'id': 1,
    });
    expect(sql, 'SELECT `:id` FROM t WHERE x = ?');
    expect(values, [1]);
  });

  test('SQL with no placeholders and no params is returned unchanged', () {
    final (sql, values) = rewrite('SELECT 1', const {});
    expect(sql, 'SELECT 1');
    expect(values, <Object?>[]);
  });

  group('the dialect changes where a literal ends', () {
    const sql = r"SELECT 'a\', :id";

    test('with backslash escapes the quote is escaped, so :id is inside', () {
      // The literal runs to the end, so there is nothing to substitute.
      expect(rewrite(sql, {'id': 1}, dialect: SqlDialect.mysql).$1, sql);
    });

    test('without them the literal ends at the quote, so :id is outside', () {
      final (rewritten, values) = rewrite(sql, {
        'id': 1,
      }, dialect: SqlDialect.mysqlWithoutBackslashEscapes);
      expect(rewritten, r"SELECT 'a\', ?");
      expect(values, [1]);
    });
  });

  group('refusing what it cannot bind', () {
    test('a name with no value', () {
      expect(
        () => rewrite('SELECT :id', const {}),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.toString(),
            'toString',
            contains('id'),
          ),
        ),
      );
    });

    test('a positional ? mixed in with names', () {
      // The two cannot be combined: the values list would have no
      // well-defined order.
      expect(
        () => rewrite('SELECT ?, :id', {'id': 1}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a value with no name in the statement is ignored, not an error', () {
      // Generated code passes a whole row's worth of parameters to
      // statements that use some of them.
      final (sql, values) = rewrite('SELECT :a', {'a': 1, 'unused': 2});
      expect(sql, 'SELECT ?');
      expect(values, [1]);
    });

    test('a null value is a value, not a missing one', () {
      final (sql, values) = rewrite('SELECT :a', {'a': null});
      expect(sql, 'SELECT ?');
      expect(values, [null]);
    });
  });
}
