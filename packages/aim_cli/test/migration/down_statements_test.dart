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
  });
}
