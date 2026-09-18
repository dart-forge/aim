import 'dart:typed_data';

import 'package:aim_sqlite/src/types/value_encoder.dart';
import 'package:test/test.dart';

SqliteBindValue encode(Object? value) => encodeValue(value, parameter: '?1');

void main() {
  test('binds the storage classes directly', () {
    expect(
      encode(7),
      isA<SqliteBindInteger>().having((v) => v.value, 'value', 7),
    );
    expect(
      encode(1.5),
      isA<SqliteBindReal>().having((v) => v.value, 'value', 1.5),
    );
    expect(
      encode('hi'),
      isA<SqliteBindText>().having((v) => v.value, 'value', 'hi'),
    );
    expect(encode(null), isA<SqliteBindNull>());
  });

  test('binds a boolean as 1 or 0, matching how a boolean column reads', () {
    expect(
      encode(true),
      isA<SqliteBindInteger>().having((v) => v.value, 'value', 1),
    );
    expect(
      encode(false),
      isA<SqliteBindInteger>().having((v) => v.value, 'value', 0),
    );
  });

  test('binds bytes as a blob', () {
    final bytes = Uint8List.fromList([1, 2]);

    expect(
      encode(bytes),
      isA<SqliteBindBlob>().having((v) => v.value, 'value', bytes),
    );
  });

  test('writes a DateTime as ISO 8601 in UTC, so the round trip holds', () {
    final local = DateTime(2026, 9, 19, 10, 0, 0);

    expect(
      encode(local),
      isA<SqliteBindText>().having(
        (v) => v.value,
        'value',
        local.toUtc().toIso8601String(),
      ),
    );
  });

  test('writes a map or a list as json', () {
    // SQLite has no array type, so a List can only mean json. Postgres had to
    // choose between an array literal and json here; this driver does not.
    expect(
      encode({'a': 1}),
      isA<SqliteBindText>().having((v) => v.value, 'value', '{"a":1}'),
    );
    expect(
      encode([1, 2]),
      isA<SqliteBindText>().having((v) => v.value, 'value', '[1,2]'),
    );
  });

  test('refuses a type it cannot represent, naming the parameter', () {
    // Falling back to toString() would silently store "Instance of 'Object'".
    expect(
      () => encodeValue(Object(), parameter: ':name'),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message.toString(),
          'message',
          contains(':name'),
        ),
      ),
    );
  });

  test('refuses a value json cannot hold', () {
    expect(() => encode([Object()]), throwsA(isA<ArgumentError>()));
  });
}
