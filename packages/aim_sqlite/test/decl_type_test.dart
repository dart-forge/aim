import 'package:aim_sqlite/src/types/decl_type.dart';
import 'package:test/test.dart';

void main() {
  group('normalizeDeclType', () {
    test('upper cases and drops the size', () {
      expect(normalizeDeclType('varchar(100)'), 'VARCHAR');
      expect(normalizeDeclType('  Decimal(10, 2) '), 'DECIMAL');
      expect(normalizeDeclType('DOUBLE PRECISION'), 'DOUBLE PRECISION');
    });

    test('passes null through', () {
      expect(normalizeDeclType(null), isNull);
    });

    test('treats an empty declaration as none', () {
      expect(normalizeDeclType('   '), isNull);
    });
  });

  group('columnKindFor', () {
    test('maps the integer family', () {
      for (final type in ['INTEGER', 'INT', 'BIGINT', 'SMALLINT', 'TINYINT']) {
        expect(columnKindFor(type), SqliteColumnKind.integer, reason: type);
      }
    });

    test('maps the floating point family', () {
      for (final type in ['REAL', 'DOUBLE', 'DOUBLE PRECISION', 'FLOAT']) {
        expect(columnKindFor(type), SqliteColumnKind.real, reason: type);
      }
    });

    test('keeps arbitrary precision decimals as text', () {
      expect(columnKindFor('NUMERIC'), SqliteColumnKind.decimalText);
      expect(columnKindFor('DECIMAL'), SqliteColumnKind.decimalText);
    });

    test('maps booleans, dates and json', () {
      expect(columnKindFor('BOOLEAN'), SqliteColumnKind.boolean);
      expect(columnKindFor('BOOL'), SqliteColumnKind.boolean);
      expect(columnKindFor('TIMESTAMP'), SqliteColumnKind.dateTime);
      expect(columnKindFor('DATETIME'), SqliteColumnKind.dateTime);
      expect(columnKindFor('DATE'), SqliteColumnKind.dateTime);
      expect(columnKindFor('JSON'), SqliteColumnKind.json);
      expect(columnKindFor('JSONB'), SqliteColumnKind.json);
      expect(columnKindFor('BLOB'), SqliteColumnKind.blob);
    });

    test('maps the text family', () {
      for (final type in ['TEXT', 'VARCHAR', 'CHAR', 'CLOB', 'UUID']) {
        expect(columnKindFor(type), SqliteColumnKind.text, reason: type);
      }
    });

    test('falls back to the storage class with no or unknown declaration', () {
      // An expression or an aggregate has no declared type; SQLite also lets
      // a column be declared with anything at all.
      expect(columnKindFor(null), SqliteColumnKind.raw);
      expect(columnKindFor('GEOMETRY'), SqliteColumnKind.raw);
    });
  });
}
