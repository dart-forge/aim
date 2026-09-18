import 'package:aim_cli/src/migration/down_statements.dart';
import 'package:test/test.dart';

void main() {
  group('executableStatements', () {
    test('drops a section that is only comments', () {
      const sql = '''
-- TODO: Cannot restore dropped table "posts" without schema backup
-- TODO: Cannot restore dropped column "age" without schema backup
''';
      expect(executableStatements(sql), isEmpty);
    });

    test('drops a section that is only a block comment', () {
      expect(executableStatements('/* nothing to do\n   here */'), isEmpty);
    });

    test('drops an empty section', () {
      expect(executableStatements(''), isEmpty);
      expect(executableStatements('   \n\n  '), isEmpty);
    });

    test('keeps a statement together with the comment above it', () {
      const sql = '''
-- Restores the column only.
ALTER TABLE users ADD COLUMN bio TEXT;
''';
      final statements = executableStatements(sql);
      expect(statements, hasLength(1));
      expect(statements.single, contains('Restores the column only.'));
      expect(statements.single, contains('ADD COLUMN bio TEXT'));
    });

    test('splits on semicolons outside comments', () {
      const sql = '''
DROP TABLE a;
DROP TABLE b;
''';
      expect(executableStatements(sql), hasLength(2));
    });

    test('does not split on a semicolon inside a line comment', () {
      const sql = '''
-- first; second; third
DROP TABLE a;
''';
      expect(executableStatements(sql), hasLength(1));
    });

    test('does not split on a semicolon inside a block comment', () {
      const sql = '''
/* first; second */
DROP TABLE a;
''';
      expect(executableStatements(sql), hasLength(1));
    });

    test('keeps a trailing statement with no semicolon', () {
      expect(executableStatements('DROP TABLE a'), hasLength(1));
    });

    test('keeps a block comment that shares a line with its statement', () {
      final statements = executableStatements('/* why */ DROP TABLE a;');
      expect(statements, hasLength(1));
      expect(statements.single, '/* why */ DROP TABLE a');
    });

    test('reads an unclosed block comment as running to the end', () {
      // The middle character of `/*/` cannot both open and close the
      // comment, so nothing after it is a statement.
      expect(executableStatements('/*/ DROP TABLE a;'), isEmpty);
    });

    test('finds the statement after a block comment whose text starts with '
        'a slash', () {
      // The slash right after `/*` belongs to the comment. Reading it as
      // the comment's close would end the comment early, split at the
      // semicolon inside it, and leave a dangling `*/` in front of the
      // real statement.
      final statements = executableStatements(
        '/*/ DROP TABLE a; */ DROP TABLE b;',
      );
      expect(statements, hasLength(1));
      expect(statements.single, '/*/ DROP TABLE a; */ DROP TABLE b');
    });

    test('does not split on a semicolon inside a string literal', () {
      const sql = "ALTER TABLE notes ALTER COLUMN kind SET DEFAULT 'a;b';";
      final statements = executableStatements(sql);
      expect(statements, hasLength(1));
      expect(
        statements.single,
        "ALTER TABLE notes ALTER COLUMN kind SET DEFAULT 'a;b'",
      );
    });

    test('reads a doubled quote as one character inside the string', () {
      const sql = "INSERT INTO notes (body) VALUES ('it''s; fine');";
      final statements = executableStatements(sql);
      expect(statements, hasLength(1));
      expect(
        statements.single,
        "INSERT INTO notes (body) VALUES ('it''s; fine')",
      );
    });

    test('does not read two dashes inside a string as a comment', () {
      const sql = "UPDATE notes SET body = '-- not a comment';";
      final statements = executableStatements(sql);
      expect(statements, hasLength(1));
      expect(statements.single, "UPDATE notes SET body = '-- not a comment'");
    });
  });
}
