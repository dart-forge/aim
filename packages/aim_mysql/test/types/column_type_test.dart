import 'dart:typed_data';

import 'package:aim_mysql/src/types/column_type.dart';
import 'package:test/test.dart';

/// A column definition packet for a column of [type].
Uint8List definition({
  required int type,
  String name = 'c',
  int charset = 33,
  int length = 20,
  int flags = 0,
  int decimals = 0,
}) {
  Iterable<int> lenenc(String s) => [s.length, ...s.codeUnits];
  return Uint8List.fromList([
    ...lenenc('def'),
    ...lenenc('db'),
    ...lenenc('t'),
    ...lenenc('t'),
    ...lenenc(name),
    ...lenenc(name),
    0x0c,
    charset & 0xff,
    charset >> 8,
    length & 0xff,
    (length >> 8) & 0xff,
    (length >> 16) & 0xff,
    length >> 24,
    type,
    flags & 0xff,
    flags >> 8,
    decimals,
    0x00,
    0x00,
  ]);
}

void main() {
  test('reads the name, the type and the flags', () {
    final column = parseColumnDefinition(
      definition(
        type: ColumnType.longLong,
        name: 'user_id',
        flags: ColumnFlags.unsigned,
      ),
    );

    expect(column.name, 'user_id');
    expect(column.type, ColumnType.longLong);
    expect(column.isUnsigned, isTrue);
  });

  test('a signed column is not unsigned', () {
    expect(
      parseColumnDefinition(definition(type: ColumnType.long)).isUnsigned,
      isFalse,
    );
  });

  group('telling TINYINT(1) from TINYINT', () {
    test('length 1 is a bool', () {
      // Confirmed against 8.4.11 and 8.0.46: BOOL and TINYINT(1) report
      // length 1, a plain TINYINT reports 4.
      expect(
        parseColumnDefinition(definition(type: ColumnType.tiny, length: 1))
            .isBool,
        isTrue,
      );
    });

    test('length 4 is not', () {
      expect(
        parseColumnDefinition(definition(type: ColumnType.tiny, length: 4))
            .isBool,
        isFalse,
      );
    });

    test('an unsigned TINYINT(1) is still a bool', () {
      // BOOL UNSIGNED is accepted by the server and still means a flag.
      expect(
        parseColumnDefinition(
          definition(
            type: ColumnType.tiny,
            length: 1,
            flags: ColumnFlags.unsigned,
          ),
        ).isBool,
        isTrue,
      );
    });

    test('nothing else is a bool, whatever its length', () {
      expect(
        parseColumnDefinition(definition(type: ColumnType.short, length: 1))
            .isBool,
        isFalse,
      );
    });
  });

  group('telling BLOB from TEXT', () {
    test('charset 63 is binary', () {
      // The type byte is the same for both. This is the only thing that
      // distinguishes them, and getting it wrong returns binary data as a
      // broken string.
      expect(
        parseColumnDefinition(
          definition(type: ColumnType.blob, charset: binaryCharsetId),
        ).isBinary,
        isTrue,
      );
    });

    test('any other charset is text', () {
      expect(
        parseColumnDefinition(definition(type: ColumnType.blob, charset: 255))
            .isBinary,
        isFalse,
      );
    });

    test('the same holds for VARCHAR against VARBINARY', () {
      expect(
        parseColumnDefinition(
          definition(type: ColumnType.varString, charset: binaryCharsetId),
        ).isBinary,
        isTrue,
      );
      expect(
        parseColumnDefinition(
          definition(type: ColumnType.varString, charset: 45),
        ).isBinary,
        isFalse,
      );
    });
  });
}
