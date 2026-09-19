import 'dart:typed_data';

import 'package:aim_sqlite/src/sqlite_exception.dart';
import 'package:aim_sqlite/src/types/decl_type.dart';
import 'package:aim_sqlite/src/types/raw_value.dart';
import 'package:aim_sqlite/src/types/value_decoder.dart';
import 'package:test/test.dart';

Object? decode(SqliteColumnKind kind, SqliteRawValue raw, {String? declType}) =>
    decodeValue(kind: kind, raw: raw, column: 'c', declType: declType);

void main() {
  test('a stored NULL is null whatever the column claims to be', () {
    for (final kind in SqliteColumnKind.values) {
      expect(decode(kind, const SqliteRawNull()), isNull, reason: '$kind');
    }
  });

  test('integers, reals and text come back as themselves', () {
    expect(decode(SqliteColumnKind.integer, const SqliteRawInteger(7)), 7);
    expect(decode(SqliteColumnKind.real, const SqliteRawReal(1.5)), 1.5);
    expect(decode(SqliteColumnKind.text, const SqliteRawText('hi')), 'hi');
  });

  test('a text column holding a blob of UTF-8 reads as that text', () {
    // TEXT affinity does not convert a blob, so a text column can hand back
    // blob storage. Bytes that are valid UTF-8 read straight through, which
    // is what keeps the guard below from failing every such column.
    expect(
      decode(
        SqliteColumnKind.text,
        SqliteRawBlob(Uint8List.fromList([104, 105])),
        declType: 'TEXT',
      ),
      'hi',
    );
  });

  test('a text column holding bytes that are not UTF-8 names the column', () {
    // Repairing these with replacement characters would be the one silent
    // corruption in the driver: the repaired string is what a caller writes
    // back, so the broken bytes would be overwritten with U+FFFD.
    expect(
      () => decode(
        SqliteColumnKind.text,
        SqliteRawBlob(Uint8List.fromList([0xFF, 0xFE, 0xFD])),
        declType: 'TEXT',
      ),
      throwsA(
        isA<SqliteDecodeException>()
            .having((e) => e.column, 'column', 'c')
            .having((e) => e.declType, 'declType', 'TEXT'),
      ),
    );
  });

  test('a decimal column stays text so money survives', () {
    expect(
      decode(SqliteColumnKind.decimalText, const SqliteRawText('10.01')),
      '10.01',
    );
    // SQLite may well have stored it as a number; it still comes back as the
    // digits, not a double.
    expect(
      decode(SqliteColumnKind.decimalText, const SqliteRawInteger(10)),
      '10',
    );
    expect(
      decode(SqliteColumnKind.decimalText, const SqliteRawReal(19.99)),
      '19.99',
    );
  });

  test('a decimal column never comes back in exponent notation', () {
    // A String whose content is `1e+21` honours the type and breaks the
    // contract: no decimal parser on the other side can read it.
    expect(
      decode(SqliteColumnKind.decimalText, const SqliteRawReal(1e21)),
      '1000000000000000000000',
    );
    expect(
      decode(SqliteColumnKind.decimalText, const SqliteRawReal(1e-7)),
      '0.0000001',
    );
    expect(
      decode(SqliteColumnKind.decimalText, const SqliteRawReal(1.5e-7)),
      '0.00000015',
    );
    expect(
      decode(SqliteColumnKind.decimalText, const SqliteRawReal(-2.5e22)),
      '-25000000000000000000000',
    );
  });

  test('a decimal column reports a stored float as it is, noise and all', () {
    // The precision was lost when this was written, not now. Rounding it here
    // would invent digits the database does not hold.
    expect(
      decode(SqliteColumnKind.decimalText, SqliteRawReal(0.1 + 0.2)),
      '0.30000000000000004',
    );
  });

  test('a boolean column reads 0 and 1', () {
    expect(decode(SqliteColumnKind.boolean, const SqliteRawInteger(1)), isTrue);
    expect(
      decode(SqliteColumnKind.boolean, const SqliteRawInteger(0)),
      isFalse,
    );
  });

  test('a boolean column rejects anything else', () {
    expect(
      () => decode(SqliteColumnKind.boolean, const SqliteRawInteger(2)),
      throwsA(isA<SqliteDecodeException>()),
    );
  });

  test('text timestamps are read as UTC', () {
    final value = decode(
      SqliteColumnKind.dateTime,
      const SqliteRawText('2026-09-19T01:02:03.000Z'),
    ) as DateTime;

    expect(value.isUtc, isTrue);
    expect(value, DateTime.utc(2026, 9, 19, 1, 2, 3));
  });

  test('a timestamp with no zone is a UTC wall clock, not local time', () {
    // The driver writes ISO 8601 with a Z, but a database built by something
    // else may hold a bare wall clock. Reading it as local time would make
    // the value depend on the server's time zone.
    final value = decode(
      SqliteColumnKind.dateTime,
      const SqliteRawText('2026-09-19 01:02:03'),
    ) as DateTime;

    expect(value.isUtc, isTrue);
    expect(value, DateTime.utc(2026, 9, 19, 1, 2, 3));
  });

  test('an integer timestamp is unix epoch seconds', () {
    final value = decode(
      SqliteColumnKind.dateTime,
      const SqliteRawInteger(1758243723),
    ) as DateTime;

    expect(value.isUtc, isTrue);
    expect(value.millisecondsSinceEpoch, 1758243723 * 1000);
  });

  test('a real timestamp is a julian day', () {
    DateTime julian(double day) =>
        decode(SqliteColumnKind.dateTime, SqliteRawReal(day)) as DateTime;

    // The julian day of the unix epoch, and one day either side of it. A
    // single point at the epoch would pass just as well with the subtraction
    // reversed or the day length mistyped, since it always yields zero.
    expect(julian(2440587.5).isUtc, isTrue);
    expect(julian(2440587.5).millisecondsSinceEpoch, 0);
    expect(julian(2440588.5).millisecondsSinceEpoch, 86400000);
    expect(julian(2440586.5).millisecondsSinceEpoch, -86400000);
  });

  test('a julian day too far out to be a DateTime names the column', () {
    // DateTime.fromMillisecondsSinceEpoch refuses anything past
    // +-8640000000000000 ms with a RangeError. Reaching the caller, that
    // RangeError comes out of a worker isolate naming no column at all,
    // while every other decode failure here carries the column, the
    // declared type and the value SQLite stored.
    expect(
      () => decode(
        SqliteColumnKind.dateTime,
        const SqliteRawReal(1e300),
        declType: 'DATETIME',
      ),
      throwsA(
        isA<SqliteDecodeException>()
            .having((e) => e.column, 'column', 'c')
            .having((e) => e.declType, 'declType', 'DATETIME')
            .having((e) => e.rawValue, 'rawValue', 1e300),
      ),
    );
  });

  test('an infinite julian day names the column', () {
    // A separate case from the one above, not a second example of it:
    // double.round() throws UnsupportedError rather than RangeError for a
    // value that is not finite, so a guard that only knew about the range
    // would let this one through.
    expect(
      () => decode(
        SqliteColumnKind.dateTime,
        SqliteRawReal(double.infinity),
        declType: 'DATETIME',
      ),
      throwsA(
        isA<SqliteDecodeException>()
            .having((e) => e.column, 'column', 'c')
            .having((e) => e.rawValue, 'rawValue', double.infinity),
      ),
    );
  });

  test(
    'an integer timestamp too far out to be a DateTime names the column',
    () {
      expect(
        () => decode(
          SqliteColumnKind.dateTime,
          const SqliteRawInteger(9007199254740993),
          declType: 'DATETIME',
        ),
        throwsA(
          isA<SqliteDecodeException>()
              .having((e) => e.column, 'column', 'c')
              .having((e) => e.rawValue, 'rawValue', 9007199254740993),
        ),
      );
    },
  );

  test(
    'an integer timestamp that overflows int64 fails instead of wrapping',
    () {
      // 2^61 seconds is the shape a range check on the milliseconds alone
      // would miss: multiplying by 1000 overflows int64 and wraps to exactly
      // zero, so this decoded to 1970-01-01 -- a wrong answer handed back
      // without a word, which is worse than the RangeError above.
      expect(
        () => decode(
          SqliteColumnKind.dateTime,
          const SqliteRawInteger(2305843009213693952),
          declType: 'DATETIME',
        ),
        throwsA(isA<SqliteDecodeException>()),
      );
    },
  );

  test('an unreadable timestamp names the column and the stored value', () {
    expect(
      () => decode(
        SqliteColumnKind.dateTime,
        const SqliteRawText('not a date'),
        declType: 'TIMESTAMP',
      ),
      throwsA(
        isA<SqliteDecodeException>()
            .having((e) => e.column, 'column', 'c')
            .having((e) => e.declType, 'declType', 'TIMESTAMP')
            .having((e) => e.rawValue, 'rawValue', 'not a date'),
      ),
    );
  });

  test('json is decoded', () {
    expect(decode(SqliteColumnKind.json, const SqliteRawText('{"a":[1,2]}')), {
      'a': [1, 2],
    });
  });

  test('broken json throws rather than handing back the string', () {
    expect(
      () => decode(SqliteColumnKind.json, const SqliteRawText('{')),
      throwsA(isA<SqliteDecodeException>()),
    );
  });

  test('a json column holding bytes that are not UTF-8 names the column', () {
    // The utf8 decode has to happen inside the same guard as the json parse,
    // or this arrives as a bare FormatException with no idea which column it
    // came from.
    expect(
      () => decode(
        SqliteColumnKind.json,
        SqliteRawBlob(Uint8List.fromList([0xFF, 0xFE, 0xFD])),
        declType: 'JSON',
      ),
      throwsA(
        isA<SqliteDecodeException>()
            .having((e) => e.column, 'column', 'c')
            .having((e) => e.declType, 'declType', 'JSON'),
      ),
    );
  });

  test('a blob column comes back as bytes', () {
    final bytes = Uint8List.fromList([1, 2, 3]);

    expect(decode(SqliteColumnKind.blob, SqliteRawBlob(bytes)), bytes);
  });

  test('a column with no declared type keeps its storage class', () {
    expect(decode(SqliteColumnKind.raw, const SqliteRawInteger(7)), 7);
    expect(decode(SqliteColumnKind.raw, const SqliteRawText('7')), '7');
    expect(decode(SqliteColumnKind.raw, const SqliteRawReal(7.5)), 7.5);
  });

  test('an integer column stored as text is read as an integer', () {
    // SQLite's type affinity is a hint, not a guarantee: a column declared
    // INTEGER can hold 'abc'. Where the text parses, honour the declaration.
    expect(decode(SqliteColumnKind.integer, const SqliteRawText('7')), 7);
  });

  test('an integer column holding unparseable text throws', () {
    expect(
      () => decode(SqliteColumnKind.integer, const SqliteRawText('abc')),
      throwsA(isA<SqliteDecodeException>()),
    );
  });
}
