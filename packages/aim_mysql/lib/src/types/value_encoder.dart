import 'dart:typed_data';

import 'package:aim_mysql/src/protocol/wire.dart';
import 'package:aim_mysql/src/types/column_type.dart';

/// One bound parameter, ready to take its place in a statement execute:
/// the wire type to declare it as, whether to mark that type unsigned, and
/// the value's already-encoded bytes.
final class EncodedParameter {
  EncodedParameter({
    required this.type,
    required this.unsigned,
    required this.bytes,
  });

  /// One of the constants on [ColumnType].
  final int type;

  /// Whether to set the unsigned bit alongside [type].
  ///
  /// Always `false` here: Dart's [int] has no unsigned form to preserve
  /// in the first place, and every other value this driver sends carries
  /// its own sign (or has none) in a way [type] already captures fully.
  final bool unsigned;

  /// The value's bytes, already in whatever shape [type] calls for --
  /// length-prefixed already for a variable-length type -- with nothing
  /// further to frame.
  final Uint8List bytes;
}

/// Encodes [value] as a bound parameter: the [ColumnType] to declare it
/// under and the bytes that go with it.
///
/// Every [int] becomes an 8-byte `LONGLONG` regardless of its size, not
/// narrowed to the smallest type that fits: the server accepts a
/// `LONGLONG` value for a column of any narrower integer type, while
/// choosing per-value would make a parameter's wire shape depend on the
/// data rather than being fixed by its Dart type.
///
/// Throws [ArgumentError], naming [value]'s runtime type, for anything not
/// listed below -- including a `List<int>` that is not a [Uint8List].
/// Such a list could be meant as bytes or could be a mistake, and this
/// driver does not guess: guessing bytes would silently accept a list of
/// ids as a blob.
EncodedParameter encodeParameter(Object? value) {
  if (value == null) {
    return EncodedParameter(
      type: ColumnType.null_,
      unsigned: false,
      bytes: Uint8List(0),
    );
  }
  if (value is bool) {
    return EncodedParameter(
      type: ColumnType.tiny,
      unsigned: false,
      bytes: Uint8List.fromList([value ? 1 : 0]),
    );
  }
  if (value is int) {
    final writer = ByteWriter()..writeUint64(value);
    return EncodedParameter(
      type: ColumnType.longLong,
      unsigned: false,
      bytes: writer.toBytes(),
    );
  }
  if (value is double) {
    final writer = ByteWriter()..writeBytes(_float64Bytes(value));
    return EncodedParameter(
      type: ColumnType.double,
      unsigned: false,
      bytes: writer.toBytes(),
    );
  }
  if (value is DateTime) {
    return EncodedParameter(
      type: ColumnType.dateTime,
      unsigned: false,
      bytes: _encodeDateTime(value),
    );
  }
  if (value is Uint8List) {
    final writer = ByteWriter()
      ..writeLengthEncodedInt(value.length)
      ..writeBytes(value);
    return EncodedParameter(
      type: ColumnType.blob,
      unsigned: false,
      bytes: writer.toBytes(),
    );
  }
  if (value is String) {
    final writer = ByteWriter()..writeLengthEncodedString(value);
    return EncodedParameter(
      type: ColumnType.varString,
      unsigned: false,
      bytes: writer.toBytes(),
    );
  }
  throw ArgumentError(
    'aim_mysql cannot encode a ${value.runtimeType} value as a bound '
    'parameter',
  );
}

/// The 8 bytes of [value] under IEEE 754 double precision, least
/// significant first.
Uint8List _float64Bytes(double value) {
  final bytes = Uint8List(8);
  ByteData.sublistView(bytes).setFloat64(0, value, Endian.little);
  return bytes;
}

/// Encodes [value] as the wire's 11-byte `DATETIME` form: a length byte of
/// `11`, then year, month, day, hour, minute and second, then the
/// fractional second as 4 bytes of whole microseconds.
///
/// Always the 11-byte form, even for a value with no fractional seconds
/// and a time of midnight: the server accepts it regardless of whether
/// the shorter 4- or 7-byte forms would also have done, and always sending
/// the same shape means this, unlike decoding, never has to branch on the
/// value.
///
/// [value] is converted to UTC first, via [DateTime.toUtc], whether or not
/// it already was: the session this driver opens is pinned to `+00:00`,
/// so sending a local wall-clock reading as though it were already UTC
/// would shift the stored value by the difference between the two.
Uint8List _encodeDateTime(DateTime value) {
  final utc = value.toUtc();
  final microsecondOfSecond = utc.millisecond * 1000 + utc.microsecond;
  final writer = ByteWriter()
    ..writeUint8(11)
    ..writeUint16(utc.year)
    ..writeUint8(utc.month)
    ..writeUint8(utc.day)
    ..writeUint8(utc.hour)
    ..writeUint8(utc.minute)
    ..writeUint8(utc.second)
    ..writeUint32(microsecondOfSecond);
  return writer.toBytes();
}
