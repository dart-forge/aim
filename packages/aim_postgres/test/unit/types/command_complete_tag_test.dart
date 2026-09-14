import 'package:aim_postgres/src/types/command_complete_tag.dart';
import 'package:test/test.dart';

void main() {
  group('affectedRowsFromCommandTag', () {
    test('INSERT carries the oid then the row count', () {
      expect(affectedRowsFromCommandTag('INSERT 0 3'), 3);
    });

    test('UPDATE / DELETE / SELECT / MERGE / COPY / FETCH', () {
      expect(affectedRowsFromCommandTag('UPDATE 2'), 2);
      expect(affectedRowsFromCommandTag('DELETE 1'), 1);
      expect(affectedRowsFromCommandTag('SELECT 5'), 5);
      expect(affectedRowsFromCommandTag('MERGE 3'), 3);
      expect(affectedRowsFromCommandTag('COPY 10'), 10);
      expect(affectedRowsFromCommandTag('FETCH 7'), 7);
    });

    test('tags without a count report 0', () {
      expect(affectedRowsFromCommandTag('CREATE TABLE'), 0);
      expect(affectedRowsFromCommandTag('BEGIN'), 0);
      expect(affectedRowsFromCommandTag('SET'), 0);
      expect(affectedRowsFromCommandTag(''), 0);
    });

    test('trailing null terminator and whitespace are ignored', () {
      expect(affectedRowsFromCommandTag('UPDATE 4\x00'), 4);
      expect(affectedRowsFromCommandTag('UPDATE 4 '), 4);
    });
  });
}
