import 'dart:convert';
import 'dart:typed_data';

import 'package:aim_mysql/src/exceptions.dart';
import 'package:aim_mysql/src/types/column_type.dart';
import 'package:aim_mysql/src/types/value_decoder.dart';
import 'package:test/test.dart';

ColumnDefinition column(
  int type, {
  int charset = 33,
  int length = 20,
  int flags = 0,
  String name = 'c',
}) => ColumnDefinition(
  name: name,
  type: type,
  flags: flags,
  columnLength: length,
  characterSet: charset,
  decimals: 0,
);

/// A binary row with no NULLs.
Uint8List row(int columnCount, List<int> values) => Uint8List.fromList([
  0x00,
  ...List.filled((columnCount + 9) ~/ 8, 0),
  ...values,
]);

List<int> lenenc(String s) => [s.length, ...s.codeUnits];

void main() {
  group('the NULL bitmap', () {
    test('is offset by two bits', () {
      // Column 0's bit is at position 2, not 0. A decoder without the
      // offset reads every column shifted and returns other columns' values
      // without any error at all.
      final payload = Uint8List.fromList([
        0x00,
        0x04, // bit 2 set: the first column is NULL
        0x2a, // the second column's value
      ]);

      expect(
        decodeBinaryRow(payload, [
          column(ColumnType.tiny),
          column(ColumnType.tiny),
        ]),
        [null, 42],
      );
    });

    test('the second column is bit three', () {
      final payload = Uint8List.fromList([0x00, 0x08, 0x2a]);

      expect(
        decodeBinaryRow(payload, [
          column(ColumnType.tiny),
          column(ColumnType.tiny),
        ]),
        [42, null],
      );
    });

    test('grows a byte every eight columns', () {
      // Six columns plus the two reserved bits is exactly one byte; seven
      // needs two.
      final sixColumns = List.filled(6, column(ColumnType.tiny));
      final sevenColumns = List.filled(7, column(ColumnType.tiny));

      expect(
        decodeBinaryRow(
          Uint8List.fromList([0x00, 0x00, 1, 2, 3, 4, 5, 6]),
          sixColumns,
        ),
        [1, 2, 3, 4, 5, 6],
      );
      expect(
        decodeBinaryRow(
          Uint8List.fromList([0x00, 0x00, 0x00, 1, 2, 3, 4, 5, 6, 7]),
          sevenColumns,
        ),
        [1, 2, 3, 4, 5, 6, 7],
      );
    });

    test('every column NULL leaves no values at all', () {
      expect(
        decodeBinaryRow(Uint8List.fromList([0x00, 0x0c]), [
          column(ColumnType.tiny),
          column(ColumnType.tiny),
        ]),
        [null, null],
      );
    });
  });

  group('integers', () {
    test('a signed TINYINT reads negative', () {
      expect(
        decodeBinaryRow(row(1, [0xff]), [column(ColumnType.tiny, length: 4)]),
        [-1],
      );
    });

    test('the same byte unsigned reads 255', () {
      // The bytes are identical; only the flag differs.
      expect(
        decodeBinaryRow(row(1, [0xff]), [
          column(ColumnType.tiny, length: 4, flags: ColumnFlags.unsigned),
        ]),
        [255],
      );
    });

    test('SHORT, LONG and LONGLONG take two, four and eight bytes', () {
      expect(
        decodeBinaryRow(row(1, [0xff, 0xff]), [column(ColumnType.short)]),
        [-1],
      );
      expect(
        decodeBinaryRow(row(1, [0xff, 0xff, 0xff, 0xff]), [
          column(ColumnType.long),
        ]),
        [-1],
      );
      expect(
        decodeBinaryRow(row(1, List.filled(8, 0xff)), [
          column(ColumnType.longLong),
        ]),
        [-1],
      );
    });

    test('INT24 still takes four bytes on the wire', () {
      // Three-byte column, four-byte value. Reading three desynchronises
      // the rest of the row.
      expect(
        decodeBinaryRow(row(2, [0x01, 0x00, 0x00, 0x00, 0x07]), [
          column(ColumnType.int24),
          column(ColumnType.tiny),
        ]),
        [1, 7],
      );
    });

    test('YEAR is an int', () {
      expect(decodeBinaryRow(row(1, [0xe8, 0x07]), [column(ColumnType.year)]), [
        2024,
      ]);
    });

    test('an unsigned BIGINT that fits is an int', () {
      expect(
        decodeBinaryRow(
          row(1, [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f]),
          [column(ColumnType.longLong, flags: ColumnFlags.unsigned)],
        ),
        [9223372036854775807],
      );
    });

    test('an unsigned BIGINT that does not fit fails loudly', () {
      // Dart's int is signed 64-bit. Reinterpreting 2^63 as negative would
      // hand back a wrong number with no sign of trouble, and turning the
      // whole column into strings would make every id column a string for
      // the sake of a value that almost never appears.
      expect(
        () => decodeBinaryRow(
          row(1, [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80]),
          [
            column(
              ColumnType.longLong,
              flags: ColumnFlags.unsigned,
              name: 'big',
            ),
          ],
        ),
        throwsA(
          isA<MySqlDecodeException>().having(
            (e) => e.toString(),
            'toString',
            contains('big'),
          ),
        ),
      );
    });
  });

  group('booleans', () {
    test('TINYINT(1) is a bool', () {
      expect(
        decodeBinaryRow(row(1, [0x01]), [column(ColumnType.tiny, length: 1)]),
        [true],
      );
      expect(
        decodeBinaryRow(row(1, [0x00]), [column(ColumnType.tiny, length: 1)]),
        [false],
      );
    });

    test('a value other than 0 or 1 is still true', () {
      // MySQL lets you store 2 in a BOOL. Treating it as true is what every
      // MySQL client does, and throwing would break a working table.
      expect(
        decodeBinaryRow(row(1, [0x02]), [column(ColumnType.tiny, length: 1)]),
        [true],
      );
    });
  });

  group('floating point', () {
    test('FLOAT is read as a float32', () {
      // Reading four bytes as a float64 gives a completely different
      // number, not a slightly less precise one.
      expect(
        decodeBinaryRow(row(1, [0x00, 0x00, 0x80, 0x3f]), [
          column(ColumnType.float),
        ]),
        [1.0],
      );
    });

    test('DOUBLE is read as a float64', () {
      final bytes = Uint8List(8)
        ..buffer.asByteData().setFloat64(0, 1.5, Endian.little);
      expect(decodeBinaryRow(row(1, bytes), [column(ColumnType.double)]), [
        1.5,
      ]);
    });
  });

  group('text and bytes', () {
    test('a string column is a String', () {
      expect(
        decodeBinaryRow(row(1, lenenc('hello')), [
          column(ColumnType.varString),
        ]),
        ['hello'],
      );
    });

    test('UTF-8 comes back intact', () {
      // Nine bytes for three characters. A decoder reading the length as a
      // character count would stop three bytes in.
      final utf8Bytes = utf8.encode('日本語');

      expect(
        decodeBinaryRow(row(1, [utf8Bytes.length, ...utf8Bytes]), [
          column(ColumnType.varString),
        ]),
        ['日本語'],
      );
    });

    test('a binary column is a Uint8List', () {
      final decoded = decodeBinaryRow(row(1, [3, 0x00, 0xff, 0x80]), [
        column(ColumnType.blob, charset: binaryCharsetId),
      ]);

      expect(decoded.single, isA<Uint8List>());
      expect(decoded.single, [0x00, 0xff, 0x80]);
    });

    test('the same type with a text charset is a String', () {
      expect(
        decodeBinaryRow(row(1, lenenc('note')), [
          column(ColumnType.blob, charset: 33),
        ]),
        ['note'],
      );
    });

    test('DECIMAL is a String, digit for digit, even on charset 63', () {
      // Which is the contract: no driver may round a decimal on the way
      // out.
      //
      // The charset here is 63, which is what a real server reports for a
      // numeric column — it means "no character set", not "give me bytes".
      // So DECIMAL must NOT go through the charset branch that turns BLOB
      // into a Uint8List; it is a String unconditionally. With the default
      // text charset this test passes either way and distinguishes
      // nothing, which is why it is pinned to 63.
      expect(
        decodeBinaryRow(row(1, lenenc('12345.6789')), [
          column(ColumnType.newDecimal, charset: binaryCharsetId),
        ]),
        ['12345.6789'],
      );
    });

    test('and DECIMAL on a text charset is still a String', () {
      // The other direction, so neither charset can be the thing that
      // decides. A server has no reason to send this, but the type's
      // mapping should not depend on a field that does not mean what the
      // BLOB case uses it for.
      expect(
        decodeBinaryRow(row(1, lenenc('0.5')), [
          column(ColumnType.newDecimal, charset: 33),
        ]),
        ['0.5'],
      );
    });

    test('BIT is a Uint8List', () {
      final decoded = decodeBinaryRow(row(1, [1, 0x05]), [
        column(ColumnType.bit, charset: binaryCharsetId),
      ]);

      expect(decoded.single, isA<Uint8List>());
      expect(decoded.single, [0x05]);
    });

    test('JSON is decoded', () {
      expect(
        decodeBinaryRow(row(1, lenenc('{"a": 1}')), [column(ColumnType.json)]),
        [
          {'a': 1},
        ],
      );
    });

    test('JSON that is not JSON fails as a decode error', () {
      expect(
        () => decodeBinaryRow(row(1, lenenc('not json')), [
          column(ColumnType.json, name: 'doc'),
        ]),
        throwsA(isA<MySqlDecodeException>()),
      );
    });

    test('GEOMETRY, which this driver does not model, becomes a String', () {
      // The contract's fallback. Better than throwing on a column the
      // caller may not even be reading.
      expect(
        decodeBinaryRow(row(1, lenenc('POINT(1 1)')), [
          column(ColumnType.geometry),
        ]),
        ['POINT(1 1)'],
      );
    });

    test(
      'GEOMETRY on the binary charset is raw bytes, not decoded as UTF-8',
      () {
        // A real GEOMETRY column reports charset 63. Real WKB geometry
        // bytes are not valid UTF-8 in general (0xff is never a valid
        // lead byte) -- decoding them unconditionally as text throws
        // MySqlProtocolException, and because that is a *protocol*
        // exception, the caller loses the whole connection over a value
        // the server sent correctly.
        final decoded = decodeBinaryRow(row(1, [3, 0x00, 0xff, 0x80]), [
          column(ColumnType.geometry, charset: binaryCharsetId),
        ]);

        expect(decoded.single, isA<Uint8List>());
        expect(decoded.single, [0x00, 0xff, 0x80]);
      },
    );

    test('so does a type byte MySQL has not assigned', () {
      expect(decodeBinaryRow(row(1, lenenc('?')), [column(0x7f)]), ['?']);
    });
  });

  group('dates', () {
    test('the four-byte form is a date at midnight UTC', () {
      final decoded = decodeBinaryRow(row(1, [4, 0xe8, 0x07, 0x09, 0x16]), [
        column(ColumnType.date),
      ]);

      expect(decoded.single, DateTime.utc(2024, 9, 22));
      expect((decoded.single as DateTime).isUtc, isTrue);
    });

    test('the seven-byte form carries the time', () {
      expect(
        decodeBinaryRow(row(1, [7, 0xe8, 0x07, 0x09, 0x16, 0x0e, 0x1e, 0x2d]), [
          column(ColumnType.dateTime),
        ]),
        [DateTime.utc(2024, 9, 22, 14, 30, 45)],
      );
    });

    test('the eleven-byte form carries microseconds', () {
      expect(
        decodeBinaryRow(
          row(1, [
            11,
            0xe8, 0x07, 0x09, 0x16, 0x0e, 0x1e, 0x2d,
            0x40, 0xe2, 0x01, 0x00, // 123456 microseconds
          ]),
          [column(ColumnType.dateTime)],
        ),
        [DateTime.utc(2024, 9, 22, 14, 30, 45, 123, 456)],
      );
    });

    test('a TIMESTAMP is UTC, because the session is pinned to +00:00', () {
      expect(
        decodeBinaryRow(row(1, [7, 0xe8, 0x07, 0x09, 0x16, 0x00, 0x00, 0x00]), [
          column(ColumnType.timestamp),
        ]),
        [DateTime.utc(2024, 9, 22)],
      );
    });

    test('the zero-length form is the zero date, and fails', () {
      // 0000-00-00 is not a date and is not null. Mapping it to null would
      // quietly turn missing data into absent data, and mapping it to year
      // zero would produce a DateTime no calendar agrees with.
      expect(
        () => decodeBinaryRow(row(1, [0]), [
          column(ColumnType.date, name: 'born'),
        ]),
        throwsA(
          isA<MySqlDecodeException>().having(
            (e) => e.toString(),
            'toString',
            contains('born'),
          ),
        ),
      );
    });

    test('a zero month or day fails the same way', () {
      expect(
        () => decodeBinaryRow(row(1, [4, 0xe8, 0x07, 0x00, 0x01]), [
          column(ColumnType.date),
        ]),
        throwsA(isA<MySqlDecodeException>()),
      );
      expect(
        () => decodeBinaryRow(row(1, [4, 0xe8, 0x07, 0x01, 0x00]), [
          column(ColumnType.date),
        ]),
        throwsA(isA<MySqlDecodeException>()),
      );
    });
  });

  group('TIME', () {
    test('is a String, not a DateTime', () {
      // It is a duration: MySQL allows -838:59:59 to 838:59:59, which no
      // time of day can hold.
      final decoded = decodeBinaryRow(
        row(1, [8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0e, 0x1e, 0x2d]),
        [column(ColumnType.time)],
      );

      expect(decoded.single, isA<String>());
      expect(decoded.single, '14:30:45');
    });

    test('carries the days into the hours', () {
      // 1 day 2 hours is 26:00:00, not 02:00:00 with a day dropped.
      expect(
        decodeBinaryRow(
          row(1, [8, 0x00, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00]),
          [column(ColumnType.time)],
        ),
        ['26:00:00'],
      );
    });

    test('a negative time keeps its sign', () {
      expect(
        decodeBinaryRow(
          row(1, [8, 0x01, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00]),
          [column(ColumnType.time)],
        ),
        ['-02:00:00'],
      );
    });

    test('the twelve-byte form carries microseconds', () {
      expect(
        decodeBinaryRow(
          row(1, [
            12,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03,
            0x40, 0xe2, 0x01, 0x00, // 123456 microseconds
          ]),
          [column(ColumnType.time)],
        ),
        ['01:02:03.123456'],
      );
    });

    test('the zero-length form is midnight, which is a valid duration', () {
      // Unlike the zero date: a zero duration means nothing is wrong.
      expect(decodeBinaryRow(row(1, [0]), [column(ColumnType.time)]), [
        '00:00:00',
      ]);
    });
  });

  group('consuming the whole row', () {
    test('trailing bytes after every column throw, not silently drop', () {
      // A mis-sized read for one column would otherwise return wrong
      // values for every later column with no error anywhere. row(1, ...)
      // builds an otherwise-correct one-column row; appending junk after
      // it is what a short read on this row (or a longer one arriving
      // where a shorter one was expected) would look like from here.
      final payload = Uint8List.fromList([
        ...row(1, [0x2a]),
        0x01,
        0x02,
        0x03,
      ]);

      expect(
        () => decodeBinaryRow(payload, [column(ColumnType.tiny)]),
        throwsA(isA<MySqlProtocolException>()),
      );
    });
  });
}
