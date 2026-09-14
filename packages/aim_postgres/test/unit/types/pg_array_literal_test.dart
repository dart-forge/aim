import 'package:aim_postgres/src/types/pg_array_literal.dart';
import 'package:test/test.dart';

void main() {
  group('parsePgArrayLiteral', () {
    test('empty array', () {
      expect(parsePgArrayLiteral('{}'), isEmpty);
    });

    test('unquoted elements', () {
      expect(parsePgArrayLiteral('{1,2,3}'), ['1', '2', '3']);
    });

    test('unquoted NULL becomes null, quoted "NULL" stays a string', () {
      expect(parsePgArrayLiteral('{1,NULL,3}'), ['1', null, '3']);
      expect(parsePgArrayLiteral('{"NULL"}'), ['NULL']);
    });

    test('quoted elements with spaces, commas and escapes', () {
      expect(
        parsePgArrayLiteral(r'{"a b","c,d","e\"f","g\\h",""}'),
        ['a b', 'c,d', 'e"f', r'g\h', ''],
      );
    });

    test('nested array is unsupported and returns null', () {
      expect(parsePgArrayLiteral('{{1,2},{3,4}}'), isNull);
    });

    test('explicit lower bound is unsupported and returns null', () {
      expect(parsePgArrayLiteral('[0:2]={1,2,3}'), isNull);
    });

    test('text that is not an array literal returns null', () {
      expect(parsePgArrayLiteral('1,2,3'), isNull);
      expect(parsePgArrayLiteral(''), isNull);
    });

    test('unterminated quote throws FormatException', () {
      expect(() => parsePgArrayLiteral('{"abc}'), throwsFormatException);
    });
  });
}
