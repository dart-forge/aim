import 'dart:typed_data';

import 'package:aim_mysql/src/types/column_type.dart';
import 'package:aim_mysql/src/types/value_encoder.dart';
import 'package:test/test.dart';

void main() {
  test('null has the NULL type and no bytes', () {
    // The bitmap says it is null; the type byte still has to be right or
    // the server reads the parameter block with the wrong layout.
    final encoded = encodeParameter(null);

    expect(encoded.type, ColumnType.null_);
    expect(encoded.bytes, isEmpty);
  });

  test('a bool is a one-byte TINYINT', () {
    expect(encodeParameter(true).type, ColumnType.tiny);
    expect(encodeParameter(true).bytes, [0x01]);
    expect(encodeParameter(false).bytes, [0x00]);
  });

  test('every int is an eight-byte LONGLONG', () {
    // Not narrowed to the smallest type that fits: the server accepts a
    // LONGLONG for a TINYINT column, and choosing per value would make the
    // parameter layout depend on the data.
    expect(encodeParameter(1).type, ColumnType.longLong);
    expect(encodeParameter(1).bytes, hasLength(8));
    expect(encodeParameter(-1).bytes, List.filled(8, 0xff));
  });

  test('a double is an eight-byte DOUBLE', () {
    expect(encodeParameter(1.5).type, ColumnType.double);
    expect(encodeParameter(1.5).bytes, hasLength(8));
  });

  test('a String is a length-encoded VAR_STRING in UTF-8', () {
    expect(encodeParameter('hi').type, ColumnType.varString);
    expect(encodeParameter('hi').bytes, [2, 0x68, 0x69]);
  });

  test('a non-ASCII String is encoded as UTF-8, with a byte length', () {
    // Three characters, nine bytes. A length in characters would truncate
    // it on the server.
    expect(encodeParameter('日本語').bytes.first, 9);
    expect(encodeParameter('日本語').bytes, hasLength(10));
  });

  test('a long String uses the length-encoded long form', () {
    final encoded = encodeParameter('a' * 300);

    expect(encoded.bytes.first, 0xfc, reason: 'the two-byte length prefix');
    expect(encoded.bytes, hasLength(303));
  });

  test('a Uint8List is a length-encoded BLOB', () {
    final encoded = encodeParameter(Uint8List.fromList([0x00, 0xff]));

    expect(encoded.type, ColumnType.blob);
    expect(encoded.bytes, [2, 0x00, 0xff]);
  });

  group('DateTime', () {
    test('is an eleven-byte DATETIME', () {
      final encoded = encodeParameter(DateTime.utc(2024, 9, 22, 14, 30, 45));

      expect(encoded.type, ColumnType.dateTime);
      expect(encoded.bytes.first, 11);
      expect(encoded.bytes, hasLength(12));
    });

    test('a local DateTime is converted to UTC first', () {
      // The session is pinned to +00:00, so sending local wall-clock
      // numbers would shift every value by the offset.
      final local = DateTime(2024, 9, 22, 14, 30, 45);

      expect(
        encodeParameter(local).bytes,
        encodeParameter(local.toUtc()).bytes,
      );
    });

    test('carries microseconds', () {
      final encoded = encodeParameter(
        DateTime.utc(2024, 9, 22, 14, 30, 45, 0, 123),
      );

      expect(encoded.bytes.sublist(8), [123, 0x00, 0x00, 0x00]);
    });
  });

  test('a type this driver cannot send is refused, naming the type', () {
    // Better than sending something the server misreads. The message has to
    // say what was passed, because the caller's map may have dozens of
    // entries.
    expect(
      () => encodeParameter(Object()),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.toString(),
          'toString',
          contains('Object'),
        ),
      ),
    );
  });

  test('a List<int> that is not a Uint8List is refused, not guessed at', () {
    // It could be bytes or it could be a mistake. Guessing bytes would
    // silently accept a list of ids as a blob.
    expect(
      () => encodeParameter(<int>[1, 2, 3]),
      throwsA(isA<ArgumentError>()),
    );
  });
}
