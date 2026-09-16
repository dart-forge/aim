import 'dart:convert';
import 'dart:typed_data';

import 'package:aim_postgres/src/types/parameter_encoder.dart';
import 'package:test/test.dart';

void main() {
  group('encodeParameterText scalars (unchanged behaviour)', () {
    test('null, int, double, String, bool, DateTime', () {
      expect(encodeParameterText(null), isNull);
      expect(encodeParameterText(42), '42');
      expect(encodeParameterText(1.5), '1.5');
      expect(encodeParameterText('abc'), 'abc');
      expect(encodeParameterText(true), 't');
      expect(encodeParameterText(false), 'f');
      expect(
        encodeParameterText(DateTime.utc(2024, 1, 2, 3, 4, 5)),
        '2024-01-02T03:04:05.000Z',
      );
    });

    test('local DateTime is sent as UTC', () {
      final local = DateTime(2024, 1, 2, 3, 4, 5);
      expect(encodeParameterText(local), local.toUtc().toIso8601String());
    });
  });

  group('encodeParameterText bytea', () {
    test(r'Uint8List becomes \x hex', () {
      expect(
        encodeParameterText(Uint8List.fromList([0x00, 0xff, 0x10])),
        r'\x00ff10',
      );
      expect(encodeParameterText(Uint8List(0)), r'\x');
    });
  });

  group('encodeParameterText Map (json)', () {
    test('Map is jsonEncoded', () {
      expect(encodeParameterText({'a': 1, 'b': [true, null]}), '{"a":1,"b":[true,null]}');
    });
  });

  group('encodeParameterText List (array literal by default)', () {
    test('numbers and bools unquoted, null as NULL', () {
      expect(encodeParameterText([1, 2, null]), '{1,2,NULL}');
      expect(encodeParameterText([true, false]), '{t,f}');
      expect(encodeParameterText(<int>[]), '{}');
    });

    test('strings are always quoted and escaped', () {
      expect(
        encodeParameterText(['a b', 'c,d', 'e"f', r'g\h', 'NULL', '']),
        r'{"a b","c,d","e\"f","g\\h","NULL",""}',
      );
    });

    test('DateTime elements are quoted ISO 8601 UTC', () {
      expect(
        encodeParameterText([DateTime.utc(2024, 1, 2)]),
        '{"2024-01-02T00:00:00.000Z"}',
      );
    });

    test('bytea elements are quoted with escaped backslash', () {
      expect(
        encodeParameterText([Uint8List.fromList([1, 2])]),
        r'{"\\x0102"}',
      );
    });

    test('Map elements (jsonb[]) are quoted json', () {
      expect(encodeParameterText([{'a': 1}]), r'{"{\"a\":1}"}');
    });

    test('nested lists become nested literals', () {
      expect(encodeParameterText([[1, 2], [3]]), '{{1,2},{3}}');
    });
  });

  group('encodeParameter', () {
    test('returns utf8 bytes, null for null', () {
      expect(encodeParameter(null), isNull);
      expect(encodeParameter('é'), Uint8List.fromList(utf8.encode('é')));
      expect(utf8.decode(encodeParameter([1, 'x'])!), '{1,"x"}');
    });
  });
}
