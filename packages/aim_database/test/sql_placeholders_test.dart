import 'package:aim_database/aim_database.dart';
import 'package:test/test.dart';

/// The name of every placeholder found, in order, with `null` for a
/// positional `?`.
///
/// Offsets are deliberately not compared here — one test below checks them,
/// and it does so by slicing the source rather than by naming an index, so
/// nobody has to count characters to read it.
List<String?> names(String sql, {SqlDialect dialect = SqlDialect.postgres}) => [
  for (final p in scanSqlPlaceholders(sql, dialect: dialect)) p.name,
];

void main() {
  group('what it finds', () {
    test('a named placeholder', () {
      expect(names('SELECT * FROM t WHERE id = :id'), ['id']);
    });

    test('a positional placeholder', () {
      expect(names('SELECT * FROM t WHERE id = ?'), [null]);
    });

    test('several, in the order they appear', () {
      expect(names('SELECT :a, :b, :c'), ['a', 'b', 'c']);
    });

    test('the same name more than once, at each position', () {
      // The caller decides what to do with the repeat. MySQL has to
      // duplicate the argument because a `?` cannot be reused; Postgres can
      // point both at one `$1`. Either way both positions get reported.
      expect(names('SELECT :id WHERE x = :id'), ['id', 'id']);
    });

    test('a name made of letters, digits and underscores', () {
      expect(names('SELECT :user_id_2'), ['user_id_2']);
    });

    test('nothing, in SQL that has no placeholders', () {
      expect(names('SELECT 1'), isEmpty);
    });

    test('reports where each placeholder sits', () {
      // Checked by slicing the source, so the expectation cannot disagree
      // with the string it is about.
      const sql = 'SELECT * FROM t WHERE id = :id AND x = ?';
      final found = scanSqlPlaceholders(sql, dialect: SqlDialect.postgres);

      expect(found, hasLength(2));
      expect(sql.substring(found[0].start, found[0].end), ':id');
      expect(sql.substring(found[1].start, found[1].end), '?');
    });
  });

  group('the longest name wins', () {
    test('a longer name is not read as a shorter one plus text', () {
      // The bug this exists to prevent: replacing `:user` first turns
      // `:user_id` into `$1_id` and loses its value.
      expect(names('SELECT :user, :user_id'), ['user', 'user_id']);
    });

    test('whichever order the names appear in', () {
      expect(names('SELECT :user_id, :user'), ['user_id', 'user']);
    });

    test('and the span covers the whole name', () {
      const sql = 'SELECT :user_id';
      final found = scanSqlPlaceholders(sql, dialect: SqlDialect.postgres);

      expect(sql.substring(found.single.start, found.single.end), ':user_id');
    });
  });

  group('what it skips', () {
    test('inside a single-quoted string', () {
      expect(names("SELECT ':id' FROM t"), isEmpty);
    });

    test('inside a string that escapes its quote by doubling', () {
      expect(names("SELECT 'it''s :id' FROM t WHERE x = :real"), ['real']);
    });

    test('inside a line comment', () {
      expect(names('SELECT 1 -- :id\nWHERE x = :real'), ['real']);
    });

    test('inside a block comment', () {
      expect(names('SELECT /* :id */ 1 WHERE x = :real'), ['real']);
    });

    test('a positional marker inside a string or a comment', () {
      expect(names("SELECT '?' -- ?\n, 1"), isEmpty);
    });

    test('an unterminated string swallows the rest', () {
      // Better to find nothing than to find a placeholder the server will
      // never see as one: the statement is already malformed.
      expect(names("SELECT ':id"), isEmpty);
    });

    test('an unterminated block comment swallows the rest', () {
      expect(names('SELECT /* :id'), isEmpty);
    });

    test('an unterminated line comment swallows the rest', () {
      expect(names('SELECT 1 -- :id'), isEmpty);
    });
  });

  group('a colon that is not a placeholder', () {
    test('a Postgres cast is not read as a placeholder', () {
      // `::int` would otherwise be found as a placeholder named `int`.
      expect(names('SELECT x::int FROM t WHERE id = :id'), ['id']);
    });

    test('a bare colon is not a placeholder', () {
      expect(names('SELECT : FROM t'), isEmpty);
    });

    test('an assignment operator is not a placeholder', () {
      expect(names('SET @x := 1', dialect: SqlDialect.mysql), isEmpty);
    });
  });

  group('Postgres', () {
    test('skips a double-quoted identifier', () {
      expect(names('SELECT ":id" FROM t'), isEmpty);
    });

    test('does not read a backslash as an escape inside a string', () {
      // standard_conforming_strings has been on by default since 9.1, so a
      // backslash is an ordinary character and the quote after it closes
      // the literal. Reading it as an escape would swallow the rest and
      // miss the real placeholder.
      expect(names(r"SELECT 'a\' , :real"), ['real']);
    });

    test('has no hash line comment', () {
      // `#` is not a comment in Postgres, so what follows it is still SQL.
      expect(names('SELECT 1 # :id'), ['id']);
    });
  });

  group('MySQL', () {
    test('skips a double-quoted string', () {
      expect(names('SELECT ":id" FROM t', dialect: SqlDialect.mysql), isEmpty);
    });

    test('skips a backtick-quoted identifier', () {
      expect(
        names('SELECT `:id` FROM t WHERE x = :real', dialect: SqlDialect.mysql),
        ['real'],
      );
    });

    test('reads a backslash as an escape inside a string by default', () {
      // MySQL escapes with a backslash unless NO_BACKSLASH_ESCAPES is set,
      // so the quote after it does not close the literal and everything up
      // to the next real quote is inside it.
      expect(
        names(r"SELECT 'a\' , :inside' , :real", dialect: SqlDialect.mysql),
        ['real'],
      );
    });

    test('stops reading it as an escape when the server says not to', () {
      // The same SQL, the other sql_mode: the literal ends at the quote
      // after the backslash, so what follows is code. This pair is why the
      // driver has to read sql_mode even though it never writes it.
      expect(
        names(
          r"SELECT 'a\' , :inside' , :real",
          dialect: SqlDialect.mysqlWithoutBackslashEscapes,
        ),
        ['inside'],
      );
    });

    test('has a hash line comment', () {
      expect(names('SELECT 1 # :id\n, :real', dialect: SqlDialect.mysql), [
        'real',
      ]);
    });

    test('-- not followed by whitespace is two unary minuses, not a '
        'comment', () {
      // MySQL only treats `--` as a comment when whitespace or a control
      // character follows. `1--:x` is the expression `1 - -:x`, so `:x`
      // is still a placeholder -- unlike Postgres, where `--` always
      // starts a comment.
      expect(names('SELECT 1--:x', dialect: SqlDialect.mysql), ['x']);
    });

    test('-- followed by whitespace is still a comment', () {
      expect(
        names('SELECT 1 -- :x\n, :real', dialect: SqlDialect.mysql),
        ['real'],
      );
    });

    test('-- at the very end of the string, with nothing after it, is '
        'still a comment', () {
      expect(names('SELECT 1 --', dialect: SqlDialect.mysql), isEmpty);
    });

    test('a backslash inside a backtick-quoted identifier is not an '
        'escape, even where a string would treat it as one', () {
      // ``a\` `` is the two-character identifier `a\`, not an escaped
      // backtick that swallows the rest of the string.
      expect(
        names(r'SELECT `a\` = :x', dialect: SqlDialect.mysql),
        ['x'],
      );
    });
  });
}
