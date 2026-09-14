import 'dart:typed_data';

import 'package:aim_postgres/src/types/pg_type_decoder.dart';
import 'package:aim_postgres/src/types/pg_type_oid.dart';
import 'package:test/test.dart';

void main() {
  group('PgTypeDecoder.decode integers', () {
    test('int2 / int4 / int8 / oid become int', () {
      expect(PgTypeDecoder.decode(PgTypeOid.int2, '-32768'), -32768);
      expect(PgTypeDecoder.decode(PgTypeOid.int4, '2147483647'), 2147483647);
      expect(
        PgTypeDecoder.decode(PgTypeOid.int8, '9223372036854775807'),
        9223372036854775807,
      );
      expect(PgTypeDecoder.decode(PgTypeOid.oid, '16384'), 16384);
    });

    test('malformed int throws FormatException', () {
      expect(
        () => PgTypeDecoder.decode(PgTypeOid.int4, 'abc'),
        throwsFormatException,
      );
    });
  });

  group('PgTypeDecoder.decode floats', () {
    test('float4 / float8 become double', () {
      expect(PgTypeDecoder.decode(PgTypeOid.float4, '1.5'), 1.5);
      expect(PgTypeDecoder.decode(PgTypeOid.float8, '-2.25e10'), -2.25e10);
    });

    test('NaN, Infinity, -Infinity', () {
      expect(
        (PgTypeDecoder.decode(PgTypeOid.float8, 'NaN') as double).isNaN,
        isTrue,
      );
      expect(
        PgTypeDecoder.decode(PgTypeOid.float8, 'Infinity'),
        double.infinity,
      );
      expect(
        PgTypeDecoder.decode(PgTypeOid.float8, '-Infinity'),
        double.negativeInfinity,
      );
    });
  });

  group('PgTypeDecoder.decode numeric', () {
    test('numeric stays String (A-043)', () {
      expect(PgTypeDecoder.decode(PgTypeOid.numeric, '1234.5600'), '1234.5600');
    });
  });

  group('PgTypeDecoder.decode bool', () {
    test('t / f', () {
      expect(PgTypeDecoder.decode(PgTypeOid.bool_, 't'), isTrue);
      expect(PgTypeDecoder.decode(PgTypeOid.bool_, 'f'), isFalse);
    });

    test('anything else throws FormatException', () {
      expect(
        () => PgTypeDecoder.decode(PgTypeOid.bool_, 'true'),
        throwsFormatException,
      );
    });
  });

  group('PgTypeDecoder.decode strings', () {
    test('text / varchar / bpchar / name / uuid stay String', () {
      expect(PgTypeDecoder.decode(PgTypeOid.text, 'a'), 'a');
      expect(PgTypeDecoder.decode(PgTypeOid.varchar, 'b'), 'b');
      expect(PgTypeDecoder.decode(PgTypeOid.bpchar, 'c  '), 'c  ');
      expect(PgTypeDecoder.decode(PgTypeOid.name, 'users'), 'users');
      expect(
        PgTypeDecoder.decode(
          PgTypeOid.uuid,
          '550e8400-e29b-41d4-a716-446655440000',
        ),
        '550e8400-e29b-41d4-a716-446655440000',
      );
    });
  });

  group('PgTypeDecoder.decode date/time (A-044: always UTC)', () {
    test('timestamp without time zone is read as UTC wall clock', () {
      final v =
          PgTypeDecoder.decode(PgTypeOid.timestamp, '2024-01-02 03:04:05.123456')
              as DateTime;
      expect(v.isUtc, isTrue);
      expect(v, DateTime.utc(2024, 1, 2, 3, 4, 5, 123, 456));
    });

    test('timestamp without fractional seconds', () {
      final v = PgTypeDecoder.decode(PgTypeOid.timestamp, '2024-01-02 03:04:05')
          as DateTime;
      expect(v, DateTime.utc(2024, 1, 2, 3, 4, 5));
    });

    test('timestamptz offsets +09, +09:30, -05 are normalized to UTC', () {
      expect(
        PgTypeDecoder.decode(PgTypeOid.timestamptz, '2024-01-02 12:00:00+09'),
        DateTime.utc(2024, 1, 2, 3, 0, 0),
      );
      expect(
        PgTypeDecoder.decode(
          PgTypeOid.timestamptz,
          '2024-01-02 12:00:00.5+09:30',
        ),
        DateTime.utc(2024, 1, 2, 2, 30, 0, 500),
      );
      expect(
        PgTypeDecoder.decode(PgTypeOid.timestamptz, '2024-01-02 12:00:00-05'),
        DateTime.utc(2024, 1, 2, 17, 0, 0),
      );
      expect(
        (PgTypeDecoder.decode(PgTypeOid.timestamptz, '2024-01-02 12:00:00+00')
                as DateTime)
            .isUtc,
        isTrue,
      );
    });

    test('date is UTC midnight', () {
      expect(
        PgTypeDecoder.decode(PgTypeOid.date, '2024-01-02'),
        DateTime.utc(2024, 1, 2),
      );
    });

    test('infinity throws FormatException', () {
      expect(
        () => PgTypeDecoder.decode(PgTypeOid.timestamp, 'infinity'),
        throwsFormatException,
      );
      expect(
        () => PgTypeDecoder.decode(PgTypeOid.timestamp, '-infinity'),
        throwsFormatException,
      );
    });

    test('time / timetz / interval stay String', () {
      expect(PgTypeDecoder.decode(PgTypeOid.time, '12:34:56'), '12:34:56');
      expect(PgTypeDecoder.decode(PgTypeOid.timetz, '12:34:56+09'), '12:34:56+09');
      expect(PgTypeDecoder.decode(PgTypeOid.interval, '1 day'), '1 day');
    });
  });

  group('PgTypeDecoder.decode json', () {
    test('json / jsonb decode objects, arrays and scalars', () {
      expect(
        PgTypeDecoder.decode(PgTypeOid.jsonb, '{"a": 1, "b": [true, null]}'),
        {'a': 1, 'b': [true, null]},
      );
      expect(PgTypeDecoder.decode(PgTypeOid.json, '[1, 2]'), [1, 2]);
      expect(PgTypeDecoder.decode(PgTypeOid.jsonb, '"s"'), 's');
      expect(PgTypeDecoder.decode(PgTypeOid.jsonb, '1'), 1);
      expect(PgTypeDecoder.decode(PgTypeOid.jsonb, 'null'), isNull);
    });

    test('broken json throws FormatException', () {
      expect(
        () => PgTypeDecoder.decode(PgTypeOid.jsonb, '{"a": '),
        throwsFormatException,
      );
    });
  });

  group('PgTypeDecoder.decode bytea', () {
    test(r'\x hex becomes Uint8List', () {
      final v = PgTypeDecoder.decode(PgTypeOid.bytea, r'\x00ff10') as Uint8List;
      expect(v, Uint8List.fromList([0x00, 0xff, 0x10]));
    });

    test('empty bytea', () {
      expect(PgTypeDecoder.decode(PgTypeOid.bytea, r'\x'), Uint8List(0));
    });

    test('escape format is unsupported and throws FormatException', () {
      expect(
        () => PgTypeDecoder.decode(PgTypeOid.bytea, r'abc\000'),
        throwsFormatException,
      );
    });
  });

  group('PgTypeDecoder unknown oid', () {
    test('forOid returns null and decode passes text through', () {
      const enumOid = 99999;
      expect(PgTypeDecoder.forOid(enumOid), isNull);
      expect(PgTypeDecoder.decode(enumOid, 'happy'), 'happy');
    });
  });
}
