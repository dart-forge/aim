import 'dart:convert';
import 'dart:typed_data';

import 'package:aim_mysql/src/exceptions.dart';
import 'package:aim_mysql/src/protocol/wire.dart';
import 'package:aim_mysql/src/types/column_type.dart';

/// Decodes one binary-protocol result row into Dart values, one per entry
/// of [columns], in the same order.
///
/// Layout:
/// ```
/// 0x00 | NULL bitmap | non-NULL values, in column order
/// ```
/// The leading `0x00` is a fixed packet-header byte and is only read past,
/// never inspected.
///
/// The NULL bitmap is `(columns.length + 7 + 2) ~/ 8` bytes: one bit per
/// column, plus 2 reserved bits at the start that this row shape carries
/// (unlike the parameter bitmap a statement execute sends, which has no
/// such offset). Column `i`'s bit is at bit position `i + 2`, so column
/// 0's bit is bit 2 of the first byte, not bit 0. Getting that offset
/// wrong does not throw: every column is read shifted by two bits, and as
/// long as the shifted bitmap still happens to mark plausible columns as
/// present, decoding proceeds and quietly hands back other columns'
/// nullness instead.
///
/// A column whose bit is set contributes nothing to the value section --
/// not even a placeholder -- and decodes to `null` here without reading
/// any bytes for it.
List<Object?> decodeBinaryRow(
  Uint8List payload,
  List<ColumnDefinition> columns,
) {
  final reader = ByteReader(payload);
  reader.readUint8(); // The 0x00 packet-header byte; always this exact value.

  final bitmapLength = (columns.length + 7 + 2) ~/ 8;
  final bitmap = reader.readBytes(bitmapLength);

  bool isNull(int columnIndex) {
    final bitPosition = columnIndex + 2;
    final byte = bitmap[bitPosition ~/ 8];
    return (byte >> (bitPosition % 8)) & 1 != 0;
  }

  final values = [
    for (var i = 0; i < columns.length; i++)
      isNull(i) ? null : _decodeValue(reader, columns[i]),
  ];

  if (!reader.atEnd) {
    // A mis-sized read for one column silently returns wrong values for
    // every later column, with no error anywhere -- the same reason
    // parseInitialHandshake checks this after reading its own last field.
    throw MySqlProtocolException(
      'a row payload had bytes left over after every column was read: read '
      '${reader.offset} of ${payload.length} byte(s)',
    );
  }

  return values;
}

/// Dispatches on [column]'s type to decode the one value at the reader's
/// current position. See the type-by-type helpers below for each shape;
/// this switch, branch for branch, is the complete mapping from wire type
/// to Dart value -- there is no separate table anywhere else it has to
/// agree with.
Object? _decodeValue(ByteReader reader, ColumnDefinition column) {
  switch (column.type) {
    case ColumnType.tiny:
      return _decodeTiny(reader, column);

    case ColumnType.short:
    case ColumnType.year:
      return _decodeFixedInt(reader, column, 16);

    case ColumnType.long:
    case ColumnType.int24:
      // INT24 (MEDIUMINT) is sent as a full 4-byte value, the same as
      // LONG, never as 3 bytes -- reading 3 here would desynchronise every
      // column after it.
      return _decodeFixedInt(reader, column, 32);

    case ColumnType.longLong:
      return _decodeLongLong(reader, column);

    case ColumnType.float:
      return ByteData.sublistView(reader.readBytes(4))
          .getFloat32(0, Endian.little);

    case ColumnType.double:
      return ByteData.sublistView(reader.readBytes(8))
          .getFloat64(0, Endian.little);

    case ColumnType.decimal:
    case ColumnType.newDecimal:
      // Always a String, digit for digit, regardless of charset: unlike
      // BLOB/VARCHAR/STRING below, a DECIMAL's charset id is not a
      // binary/text signal to branch on -- the contract is that no driver
      // rounds a decimal on the way out, full stop.
      return _decodeUtf8Value(_readLenencBytes(reader), column);

    case ColumnType.date:
    case ColumnType.dateTime:
    case ColumnType.timestamp:
      return _decodeDateTime(reader, column);

    case ColumnType.time:
      return _decodeTime(reader);

    case ColumnType.json:
      return _decodeJson(reader, column);

    case ColumnType.bit:
      // Always raw bytes: a BIT column has no text form to distinguish it
      // from.
      return _readLenencBytes(reader);

    case ColumnType.blob:
    case ColumnType.tinyBlob:
    case ColumnType.mediumBlob:
    case ColumnType.longBlob:
    case ColumnType.varString:
    case ColumnType.varChar:
    case ColumnType.string:
    case ColumnType.enum_:
    case ColumnType.set:
      // BLOB and TEXT (of every size) share their type byte, as do
      // VARBINARY/VARCHAR and BINARY/CHAR. The charset id is the only
      // signal that tells the binary half of each pair from the text
      // half; getting it backwards hands back binary data as a broken
      // string, or text as bytes.
      final bytes = _readLenencBytes(reader);
      return column.isBinary ? bytes : _decodeUtf8Value(bytes, column);

    default:
      // GEOMETRY, which this driver does not model into any structured
      // type, and any type byte MySQL has assigned that this driver does
      // not otherwise recognise. Charset-branched exactly like the
      // BLOB/TEXT case above: a real GEOMETRY column reports charset 63
      // (binaryCharsetId), and decoding its WKB bytes as UTF-8
      // unconditionally would throw MySqlProtocolException for a value
      // the server sent correctly -- and because that exception is a
      // *protocol* one, the caller loses the whole connection over it, not
      // just this value.
      final bytes = _readLenencBytes(reader);
      return column.isBinary ? bytes : _decodeUtf8Value(bytes, column);
  }
}

/// Decodes [bytes] as UTF-8 for [column]'s value, the same way
/// [decodeUtf8] does, but on bad bytes throws [MySqlDecodeException]
/// instead of [MySqlProtocolException].
///
/// A short or misaligned read desynchronises every column after it and
/// deserves to take the whole connection down with [MySqlProtocolException];
/// bytes that are simply not valid UTF-8 do not -- the stream is still in
/// step, the row's other columns are still readable, and the caller should
/// get a per-value error naming the column, not lose the connection over
/// one bad string.
String _decodeUtf8Value(Uint8List bytes, ColumnDefinition column) {
  try {
    return decodeUtf8(bytes);
  } on MySqlProtocolException catch (e) {
    throw MySqlDecodeException(
      'column "${column.name}" is not valid UTF-8: ${e.message}',
    );
  }
}

/// Decodes a `TINYINT`: a `bool` if [ColumnDefinition.isBool] says this is
/// really a `BOOL`/`TINYINT(1)`, otherwise a plain signed or unsigned
/// one-byte integer.
Object _decodeTiny(ByteReader reader, ColumnDefinition column) {
  if (column.isBool) {
    // MySQL lets a BOOL hold any TINYINT value, not just 0 and 1; every
    // other MySQL client treats anything nonzero as true, and throwing on
    // a 2 would break a table that already has one stored.
    return reader.readUint8() != 0;
  }
  return _decodeFixedInt(reader, column, 8);
}

/// Decodes a fixed-width integer of [bits] bits (8, 16 or 32), applying
/// [ColumnDefinition.isUnsigned] to decide whether the top bit is a sign
/// or more magnitude.
///
/// Signedness lives entirely in [column]'s flags, not in the bytes: the
/// same byte pattern is negative for a signed column and a larger
/// positive number for an unsigned one.
int _decodeFixedInt(ByteReader reader, ColumnDefinition column, int bits) {
  final raw = switch (bits) {
    8 => reader.readUint8(),
    16 => reader.readUint16(),
    32 => reader.readUint32(),
    _ => throw ArgumentError('unsupported integer width: $bits bits'),
  };
  if (column.isUnsigned) {
    return raw;
  }
  final signBit = 1 << (bits - 1);
  return raw & signBit != 0 ? raw - (1 << bits) : raw;
}

/// Decodes a `BIGINT`.
///
/// [ByteReader.readUint64] already hands back the bytes' plain
/// two's-complement reading, which is exactly the signed value wanted when
/// [ColumnDefinition.isUnsigned] is false, including when that reading is
/// negative. For an unsigned column, a negative reading instead means the
/// true value is at or above 2^63: too large for Dart's signed 64-bit
/// [int] to hold at all. Reinterpreting it as the negative number the bits
/// happen to spell would be a wrong value with no sign anything went
/// wrong, so this throws by name instead.
int _decodeLongLong(ByteReader reader, ColumnDefinition column) {
  final raw = reader.readUint64();
  if (column.isUnsigned && raw < 0) {
    throw MySqlDecodeException(
      'column "${column.name}" is BIGINT UNSIGNED with a value at or '
      'above 2^63, which does not fit in a Dart int',
    );
  }
  return raw;
}

/// Reads a length-encoded byte string: a length-encoded integer, then that
/// many raw bytes. The shared shape behind every `DECIMAL`, string,
/// `BLOB`, `JSON`, `ENUM`, `SET`, `BIT` and `GEOMETRY` value, and the
/// fallback for a type byte this driver does not otherwise recognise.
Uint8List _readLenencBytes(ByteReader reader) {
  final length = reader.readLengthEncodedInt();
  if (length == null) {
    // The lenenc NULL marker (0xfb) never legitimately appears for a row
    // value: NULL-ness is carried entirely by the bitmap decodeBinaryRow
    // already consulted, so reaching this means the stream is out of step.
    throw MySqlProtocolException(
      'a row value used the length-encoded-integer NULL marker (0xfb); '
      'NULL-ness is carried by the row bitmap, not by a value marker',
    );
  }
  return reader.readBytes(length);
}

/// Decodes a `JSON` value: the underlying bytes are a length-encoded UTF-8
/// string holding JSON text, which is then parsed.
Object? _decodeJson(ByteReader reader, ColumnDefinition column) {
  final text = _decodeUtf8Value(_readLenencBytes(reader), column);
  try {
    return jsonDecode(text);
  } on FormatException catch (e) {
    throw MySqlDecodeException(
      'column "${column.name}" is JSON but its value is not valid JSON: $e',
    );
  }
}

/// The lengths a `DATE`/`DATETIME`/`TIMESTAMP` value's own 1-byte length
/// field may legitimately hold.
const _validDateTimeLengths = {0, 4, 7, 11};

/// Decodes a `DATE`, `DATETIME` or `TIMESTAMP` value.
///
/// Layout: a 1-byte length, then that many bytes --
/// ```
/// 0   -- nothing follows: the zero date, 0000-00-00.
/// 4   -- int2 year | int1 month | int1 day
/// 7   -- the above, then int1 hour | int1 minute | int1 second
/// 11  -- the above, then int4 microsecond
/// ```
/// `TIMESTAMP` uses the same shapes as `DATETIME`; which of the three
/// types [column] names does not change how the bytes are read, only that
/// the caller knows it is pinned to UTC either way.
///
/// The zero-length form, and a length-4-or-more form whose month or day is
/// `0`, both mean `0000-00-00`: not a real date, and not the same thing as
/// SQL NULL. Mapping either to `null` would silently turn a recorded
/// "unset" value into an absent one; mapping it to year zero would produce
/// a [DateTime] no calendar agrees with. Both throw [MySqlDecodeException]
/// naming [column] instead.
DateTime _decodeDateTime(ByteReader reader, ColumnDefinition column) {
  final length = reader.readUint8();
  if (!_validDateTimeLengths.contains(length)) {
    throw MySqlProtocolException(
      'a DATE/DATETIME/TIMESTAMP value declared a length of $length, but '
      'only 0, 4, 7 or 11 is valid',
    );
  }
  if (length == 0) {
    throw MySqlDecodeException(
      'column "${column.name}" is the zero date (0000-00-00), which this '
      'driver does not map to null or to any real DateTime',
    );
  }

  final year = reader.readUint16();
  final month = reader.readUint8();
  final day = reader.readUint8();
  if (month == 0 || day == 0) {
    throw MySqlDecodeException(
      'column "${column.name}" has a zero month or day, which this driver '
      'does not map to null or to any real DateTime',
    );
  }

  var hour = 0;
  var minute = 0;
  var second = 0;
  if (length >= 7) {
    hour = reader.readUint8();
    minute = reader.readUint8();
    second = reader.readUint8();
  }
  var microsecond = 0;
  if (length == 11) {
    microsecond = reader.readUint32();
  }

  return DateTime.utc(
    year,
    month,
    day,
    hour,
    minute,
    second,
    microsecond ~/ 1000,
    microsecond % 1000,
  );
}

/// Decodes a `TIME` value into a [String], never a [DateTime]: MySQL's
/// `TIME` holds a signed duration from -838:59:59 to 838:59:59, a range no
/// time-of-day type can represent, and the days field folds into the hour
/// count rather than being carried (or dropped) separately.
///
/// Layout: a 1-byte length, then that many bytes --
/// ```
/// 0   -- nothing follows: a zero duration, unlike the DATE/DATETIME zero
///        form this is a perfectly ordinary value, not an error.
/// 8   -- int1 is_negative | int4 days | int1 hour | int1 minute | int1 second
/// 12  -- the above, then int4 microsecond
/// ```
String _decodeTime(ByteReader reader) {
  final length = reader.readUint8();
  if (length == 0) {
    return '00:00:00';
  }
  if (length != 8 && length != 12) {
    throw MySqlProtocolException(
      'a TIME value declared a length of $length, but only 0, 8 or 12 is '
      'valid',
    );
  }

  final isNegative = reader.readUint8() != 0;
  final days = reader.readUint32();
  final hour = reader.readUint8();
  final minute = reader.readUint8();
  final second = reader.readUint8();
  final microsecond = length == 12 ? reader.readUint32() : 0;

  final totalHours = days * 24 + hour;
  final buffer = StringBuffer(isNegative ? '-' : '')
    ..write(totalHours.toString().padLeft(2, '0'))
    ..write(':')
    ..write(minute.toString().padLeft(2, '0'))
    ..write(':')
    ..write(second.toString().padLeft(2, '0'));
  if (microsecond != 0) {
    buffer
      ..write('.')
      ..write(microsecond.toString().padLeft(6, '0'));
  }
  return buffer.toString();
}
