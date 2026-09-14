import 'dart:convert';
import 'dart:typed_data';

import 'package:aim_postgres/src/types/pg_array_literal.dart';
import 'package:aim_postgres/src/types/pg_type_oid.dart';

/// Converts the text-format representation of one PostgreSQL value into a
/// Dart value. Throws [FormatException] when the text cannot be decoded.
typedef PgDecoder = Object? Function(String text);

/// Text-format decoders for PostgreSQL types, keyed by type OID.
///
/// Contract (A-041, A-043, A-044, A-046):
/// - Known types are converted to Dart values; `numeric` stays [String].
/// - [DateTime] values are always UTC. `timestamp` without time zone is read
///   as a UTC wall clock, matching how parameters are sent.
/// - Unknown OIDs are not an error: [forOid] returns `null` and [decode]
///   returns the text unchanged.
abstract final class PgTypeDecoder {
  static final Map<int, PgDecoder> _scalar = {
    PgTypeOid.int2: int.parse,
    PgTypeOid.int4: int.parse,
    PgTypeOid.int8: int.parse,
    PgTypeOid.oid: int.parse,
    PgTypeOid.float4: double.parse,
    PgTypeOid.float8: double.parse,
    PgTypeOid.numeric: _identity,
    PgTypeOid.bool_: _decodeBool,
    PgTypeOid.text: _identity,
    PgTypeOid.varchar: _identity,
    PgTypeOid.bpchar: _identity,
    PgTypeOid.name: _identity,
    PgTypeOid.uuid: _identity,
    PgTypeOid.timestamp: _decodeTimestamp,
    PgTypeOid.timestamptz: _decodeTimestamptz,
    PgTypeOid.date: _decodeDate,
    PgTypeOid.time: _identity,
    PgTypeOid.timetz: _identity,
    PgTypeOid.interval: _identity,
    PgTypeOid.json: _decodeJson,
    PgTypeOid.jsonb: _decodeJson,
    PgTypeOid.bytea: _decodeBytea,
  };

  /// Returns the decoder for [typeOid], or `null` when the type is not
  /// supported (the caller then keeps the raw text).
  ///
  /// One-dimensional arrays of supported scalar types decode to
  /// `List<Object?>`; shapes [parsePgArrayLiteral] rejects (nested arrays,
  /// explicit bounds) are returned as the raw text.
  static PgDecoder? forOid(int typeOid) {
    final scalar = _scalar[typeOid];
    if (scalar != null) return scalar;
    final elementOid = PgTypeOid.arrayElement[typeOid];
    if (elementOid == null) return null;
    final elementDecoder = _scalar[elementOid];
    if (elementDecoder == null) return null;
    return (text) => _decodeArray(text, elementDecoder);
  }

  static Object? _decodeArray(String text, PgDecoder element) {
    final parts = parsePgArrayLiteral(text);
    if (parts == null) return text;
    return [for (final p in parts) p == null ? null : element(p)];
  }

  /// Decodes [text] as [typeOid]. Unknown types return [text] unchanged.
  static Object? decode(int typeOid, String text) {
    final decoder = forOid(typeOid);
    return decoder == null ? text : decoder(text);
  }

  static Object? _identity(String text) => text;

  static Object? _decodeBool(String text) => switch (text) {
        't' => true,
        'f' => false,
        _ => throw FormatException('Invalid boolean literal', text),
      };

  // PostgreSQL prints `2024-01-02 03:04:05.123456`. Appending `Z` makes
  // DateTime.parse treat it as UTC instead of the local zone (A-044).
  static Object? _decodeTimestamp(String text) {
    _rejectSpecialTimestamp(text);
    return DateTime.parse('${text}Z');
  }

  // PostgreSQL prints `2024-01-02 12:00:00+09` (offset may be `+hh`,
  // `+hh:mm`, or `+hh:mm:ss`). DateTime.parse resolves the offset and
  // returns a UTC value.
  static Object? _decodeTimestamptz(String text) {
    _rejectSpecialTimestamp(text);
    return DateTime.parse(text).toUtc();
  }

  static Object? _decodeDate(String text) {
    _rejectSpecialTimestamp(text);
    return DateTime.parse('${text}T00:00:00Z');
  }

  static void _rejectSpecialTimestamp(String text) {
    if (text == 'infinity' || text == '-infinity' || text.endsWith(' BC')) {
      throw FormatException('Timestamp cannot be represented as DateTime', text);
    }
  }

  static Object? _decodeJson(String text) => jsonDecode(text);

  // Only the hex output format (`\x...`, the default since 9.0) is
  // supported. The legacy escape format is rejected.
  static Object? _decodeBytea(String text) {
    if (!text.startsWith(r'\x')) {
      throw FormatException('Unsupported bytea format (expected \\x hex)', text);
    }
    final hex = text.substring(2);
    if (hex.length.isOdd) {
      throw FormatException('Odd-length bytea hex', text);
    }
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}
