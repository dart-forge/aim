import 'dart:convert';
import 'dart:typed_data';

import 'package:aim_postgres/src/types/pg_type_oid.dart';
import 'package:aim_postgres/src/types/query_result_decoder.dart';
import 'package:test/test.dart';

Map<String, dynamic> column(String name, int typeOid, {int formatCode = 0}) => {
      'name': name,
      'tableOid': 0,
      'columnAttr': 0,
      'typeOid': typeOid,
      'typeSize': 0,
      'typeMod': -1,
      'formatCode': formatCode,
    };

Uint8List text(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('resolveColumnDecoders', () {
    test('one decoder per column; unknown oid and binary format give null', () {
      final decoders = resolveColumnDecoders([
        column('id', PgTypeOid.int4),
        column('mood', 99999),
        column('blob', PgTypeOid.bytea, formatCode: 1),
      ]);
      expect(decoders.length, 3);
      expect(decoders[0], isNotNull);
      expect(decoders[1], isNull);
      expect(decoders[2], isNull);
    });
  });

  group('decodeRows', () {
    final columns = [
      column('id', PgTypeOid.int4),
      column('ok', PgTypeOid.bool_),
      column('at', PgTypeOid.timestamp),
      column('mood', 99999),
      column('raw', PgTypeOid.int4, formatCode: 1),
    ];

    test('decodes text cells by column type, keeps unknown as String and binary as bytes', () {
      final rows = decodeRows(columns, [
        [
          text('7'),
          text('t'),
          text('2024-01-02 03:04:05'),
          text('happy'),
          Uint8List.fromList([0, 0, 0, 7]),
        ],
      ]);
      expect(rows, [
        [
          7,
          true,
          DateTime.utc(2024, 1, 2, 3, 4, 5),
          'happy',
          Uint8List.fromList([0, 0, 0, 7]),
        ],
      ]);
    });

    test('NULL cells stay null', () {
      final rows = decodeRows(columns, [
        [null, null, null, null, null],
      ]);
      expect(rows, [
        [null, null, null, null, null],
      ]);
    });

    test('decode failure throws PostgresDecodeException with column details', () {
      expect(
        () => decodeRows(columns, [
          [text('7'), text('maybe'), text('2024-01-02 03:04:05'), null, null],
        ]),
        throwsA(
          isA<PostgresDecodeException>()
              .having((e) => e.columnName, 'columnName', 'ok')
              .having((e) => e.typeOid, 'typeOid', PgTypeOid.bool_)
              .having((e) => e.rawValue, 'rawValue', 'maybe')
              .having((e) => e.cause, 'cause', isA<FormatException>()),
        ),
      );
    });

    test('row with wrong cell count throws PostgresDecodeException, not RangeError', () {
      expect(
        () => decodeRows(columns, [
          [text('7'), text('t')],
        ]),
        throwsA(
          isA<PostgresDecodeException>()
              .having((e) => e.columnName, 'columnName', '<row>')
              .having((e) => e.typeOid, 'typeOid', 0)
              .having(
                (e) => e.rawValue,
                'rawValue',
                'DataRow has 2 cells for ${columns.length} columns',
              ),
        ),
      );
    });

    test('toString names the column and raw value', () {
      final e = PostgresDecodeException(
        columnName: 'at',
        typeOid: PgTypeOid.timestamp,
        rawValue: 'infinity',
        cause: const FormatException('x'),
      );
      expect(e.toString(), contains('"at"'));
      expect(e.toString(), contains('infinity'));
      expect(e.toString(), contains('1114'));
    });
  });
}
