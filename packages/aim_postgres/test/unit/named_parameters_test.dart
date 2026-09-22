import 'package:aim_postgres/src/named_parameters.dart';
import 'package:test/test.dart';

void main() {
  group('what it converts', () {
    test('one named parameter', () {
      final (sql, values) = convertNamedParameters(
        'SELECT * FROM users WHERE id = :id',
        {'id': 7},
      );

      expect(sql, 'SELECT * FROM users WHERE id = \$1');
      expect(values, [7]);
    });

    test('several, numbered in the order they appear in the SQL', () {
      // Not the order of the map: the server matches $1 to the first value,
      // so the numbering has to follow the statement.
      final (sql, values) = convertNamedParameters(
        'SELECT * FROM t WHERE a = :second AND b = :first',
        {'first': 'F', 'second': 'S'},
      );

      expect(sql, 'SELECT * FROM t WHERE a = \$1 AND b = \$2');
      expect(values, ['S', 'F']);
    });

    test('a name used twice points both positions at one value', () {
      // Postgres allows a placeholder to be reused, so the value is sent
      // once. (MySQL cannot do this, which is why its driver duplicates.)
      final (sql, values) = convertNamedParameters(
        'SELECT * FROM t WHERE a = :x OR b = :x',
        {'x': 1},
      );

      expect(sql, 'SELECT * FROM t WHERE a = \$1 OR b = \$1');
      expect(values, [1]);
    });

    test('no parameters at all', () {
      final (sql, values) = convertNamedParameters('SELECT 1', {});

      expect(sql, 'SELECT 1');
      expect(values, isEmpty);
    });
  });

  group('a name that is a prefix of another', () {
    test('does not eat the longer name', () {
      // The bug this test exists for. Replacing `:user` first turned
      // `:user_id` into `$1_id`, which is a syntax error, and then
      // `contains(':user_id')` was false so its value was never sent.
      final (sql, values) = convertNamedParameters(
        'SELECT * FROM t WHERE name = :user AND uid = :user_id',
        {'user': 'alice', 'user_id': 7},
      );

      expect(sql, 'SELECT * FROM t WHERE name = \$1 AND uid = \$2');
      expect(values, ['alice', 7]);
    });

    test('whichever order the map happens to be in', () {
      // Map iteration follows insertion order, so the old code's behaviour
      // depended on which key the caller wrote first. This one must not.
      final (sql, values) = convertNamedParameters(
        'SELECT * FROM t WHERE name = :user AND uid = :user_id',
        {'user_id': 7, 'user': 'alice'},
      );

      expect(sql, 'SELECT * FROM t WHERE name = \$1 AND uid = \$2');
      expect(values, ['alice', 7]);
    });
  });

  group('what it leaves alone', () {
    test('a colon inside a string literal', () {
      // The old code replaced here too, corrupting the literal.
      final (sql, values) = convertNamedParameters(
        "SELECT * FROM t WHERE note = ':id' AND id = :id",
        {'id': 7},
      );

      expect(sql, "SELECT * FROM t WHERE note = ':id' AND id = \$1");
      expect(values, [7]);
    });

    test('a colon inside a line comment', () {
      final (sql, values) = convertNamedParameters(
        'SELECT 1 -- :id\nWHERE id = :id',
        {'id': 7},
      );

      expect(sql, 'SELECT 1 -- :id\nWHERE id = \$1');
      expect(values, [7]);
    });

    test('a colon inside a block comment', () {
      final (sql, values) = convertNamedParameters(
        'SELECT /* :id */ 1 WHERE id = :id',
        {'id': 7},
      );

      expect(sql, 'SELECT /* :id */ 1 WHERE id = \$1');
      expect(values, [7]);
    });

    test('a cast', () {
      final (sql, values) = convertNamedParameters(
        'SELECT x::int FROM t WHERE id = :id',
        {'id': 7},
      );

      expect(sql, 'SELECT x::int FROM t WHERE id = \$1');
      expect(values, [7]);
    });

    test('a quoted identifier', () {
      final (sql, values) = convertNamedParameters(
        'SELECT ":id" FROM t WHERE id = :id',
        {'id': 7},
      );

      expect(sql, 'SELECT ":id" FROM t WHERE id = \$1');
      expect(values, [7]);
    });
  });

  group('what it refuses', () {
    test('a placeholder with no value', () {
      // Sending the statement with a $1 nothing binds would fail at the
      // server with a message about the parameter count, which points at
      // the wrong thing.
      expect(
        () => convertNamedParameters('SELECT :missing', {'other': 1}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('and says which name it could not find', () {
      expect(
        () => convertNamedParameters('SELECT :missing', {'other': 1}),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.toString(),
            'message',
            contains('missing'),
          ),
        ),
      );
    });

    test('a positional marker mixed in with named parameters', () {
      // The statement would then need both a params map and an args list,
      // which the caller cannot express and _runQuery already rejects.
      expect(
        () => convertNamedParameters('SELECT :a, ?', {'a': 1}),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('a value that is passed but never used', () {
    test('is left out rather than sent', () {
      // The old code behaved this way too: a key the SQL never mentions is
      // skipped. Kept deliberately — the ORM builds one map and reuses it
      // across statements that each mention a subset.
      final (sql, values) = convertNamedParameters(
        'SELECT * FROM t WHERE id = :id',
        {'id': 7, 'unused': 'x'},
      );

      expect(sql, 'SELECT * FROM t WHERE id = \$1');
      expect(values, [7]);
    });
  });
}
