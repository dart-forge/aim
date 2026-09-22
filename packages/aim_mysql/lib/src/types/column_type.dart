import 'dart:typed_data';

import 'package:aim_mysql/src/exceptions.dart';
import 'package:aim_mysql/src/protocol/wire.dart';

/// The charset id that marks a column as raw bytes rather than text.
///
/// A handful of types share one type byte between a binary form and a
/// text form -- [ColumnType.blob] doubles as `TEXT`, [ColumnType.varString]
/// doubles as `VARBINARY`, [ColumnType.string] doubles as `BINARY`. This
/// charset id, and nothing about the type byte itself, is what tells the
/// two apart. Getting that check wrong hands binary data back as a broken
/// string, or text back as bytes.
const int binaryCharsetId = 63;

/// The type byte a column definition or a bound parameter carries on the
/// wire -- MySQL's own `enum_field_types`, one constant per value this
/// driver actually branches on.
///
/// Named `null_` because `null` is a reserved word in Dart. Every other
/// name is the server's own, lowerCamelCased.
abstract final class ColumnType {
  static const int decimal = 0;
  static const int tiny = 1;
  static const int short = 2;
  static const int long = 3;
  static const int float = 4;
  static const int double = 5;
  static const int null_ = 6;
  static const int timestamp = 7;
  static const int longLong = 8;
  static const int int24 = 9;
  static const int date = 10;
  static const int time = 11;
  static const int dateTime = 12;
  static const int year = 13;
  static const int varChar = 15;
  static const int bit = 16;
  static const int json = 245;
  static const int newDecimal = 246;
  static const int enum_ = 247;
  static const int set = 248;
  static const int tinyBlob = 249;
  static const int mediumBlob = 250;
  static const int longBlob = 251;
  static const int blob = 252;
  static const int varString = 253;
  static const int string = 254;
  static const int geometry = 255;
}

/// Bits of a column definition's `flags` field that this driver reads.
abstract final class ColumnFlags {
  /// Set when the column is declared `UNSIGNED`.
  ///
  /// This is the only place signedness lives: the bytes of, say, a
  /// `TINYINT` holding `0xff` are the same whether the column is signed or
  /// not. Reading this flag is what decides whether they mean `-1` or
  /// `255` -- see `value_decoder.dart`.
  static const int unsigned = 0x0020;
}

/// One column's shape, as sent in a result set's metadata ahead of every
/// row, or synthesized by a caller decoding a row by hand (see the
/// constructor).
final class ColumnDefinition {
  ColumnDefinition({
    required this.name,
    required this.type,
    required this.flags,
    required this.columnLength,
    required this.characterSet,
    required this.decimals,
  });

  /// The column's name, or its alias if the query gave it one.
  final String name;

  /// One of the constants on [ColumnType].
  final int type;

  /// The raw flags bitmask; see [ColumnFlags] and [isUnsigned].
  final int flags;

  /// The display width the server suggests for this column.
  ///
  /// Not a byte count. For [ColumnType.tiny] specifically, it doubles as
  /// the only way to tell a `BOOL`/`TINYINT(1)` from a plain `TINYINT` --
  /// see [isBool].
  final int columnLength;

  /// The column's charset id. [binaryCharsetId] means "raw bytes"; see
  /// [isBinary].
  final int characterSet;

  /// Digits after the decimal point, for a fixed- or floating-point type.
  final int decimals;

  /// Whether [ColumnFlags.unsigned] is set.
  ///
  /// Decides how the same bytes are read for every integer type: with this
  /// set, the high bit of the value is just another bit of magnitude
  /// rather than a sign.
  bool get isUnsigned => flags & ColumnFlags.unsigned != 0;

  /// Whether [characterSet] is [binaryCharsetId] -- i.e., for a type that
  /// shares its type byte between a binary and a text form, this is the
  /// binary half of the pair.
  bool get isBinary => characterSet == binaryCharsetId;

  /// Whether this is a `BOOL` or `TINYINT(1)` rather than a plain
  /// `TINYINT`.
  ///
  /// Both send [ColumnType.tiny] as their type byte; the server tells them
  /// apart only by [columnLength], which is `1` for the boolean-shaped
  /// column and `4` for a plain `TINYINT` (confirmed against real 8.0 and
  /// 8.4 servers -- this is not documented anywhere that promises it).
  /// Independent of [isUnsigned]: `BOOL UNSIGNED` is accepted by the server
  /// and still means a flag, not a wider integer.
  bool get isBool => type == ColumnType.tiny && columnLength == 1;
}

/// Parses one `ColumnDefinition41` packet: one entry of a result set's
/// column metadata, sent once per column ahead of the rows themselves.
///
/// Layout:
/// ```
/// lenenc catalog ("def") | lenenc schema | lenenc table | lenenc org_table
/// | lenenc name | lenenc org_name
/// | lenenc 0x0c | int2 charset | int4 column_length | int1 type
/// | int2 flags | int1 decimals | int2 filler
/// ```
/// Everything before `name` is read and discarded: this driver has no use
/// for the catalog, schema, table names or the column's un-aliased name.
/// The `lenenc 0x0c` is the length of the six fixed-width fields that
/// follow it (always 12, i.e. `2 + 4 + 1 + 2 + 1 + 2`); it is read to stay
/// in step with the packet and otherwise ignored, since those fields are
/// fixed-width regardless of what it says.
ColumnDefinition parseColumnDefinition(Uint8List payload) {
  final reader = ByteReader(payload);
  reader.readLengthEncodedString(); // catalog -- always "def".
  reader.readLengthEncodedString(); // schema.
  reader.readLengthEncodedString(); // table.
  reader.readLengthEncodedString(); // org_table.
  final name = reader.readLengthEncodedString();
  reader.readLengthEncodedString(); // org_name.
  reader.readLengthEncodedInt(); // Length of the fixed fields below.

  final characterSet = reader.readUint16();
  final columnLength = reader.readUint32();
  final type = reader.readUint8();
  final flags = reader.readUint16();
  final decimals = reader.readUint8();
  reader.skip(2); // Filler; always 0x0000.

  if (name == null) {
    // The lenenc NULL marker (0xfb) is not a value a real column
    // definition ever uses for its name; treating it as an empty string
    // would silently hide a stream that is already out of step.
    throw MySqlProtocolException(
      "a column definition's name was the length-encoded-integer NULL "
      'marker (0xfb), which never happens for a real column',
    );
  }

  return ColumnDefinition(
    name: name,
    type: type,
    flags: flags,
    columnLength: columnLength,
    characterSet: characterSet,
    decimals: decimals,
  );
}
