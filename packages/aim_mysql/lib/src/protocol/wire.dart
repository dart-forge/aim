import 'dart:convert';
import 'dart:typed_data';

import 'package:aim_mysql/src/exceptions.dart';

/// Reads the primitives of the MySQL wire protocol out of a fixed byte
/// buffer: little-endian integers, length-encoded integers, and the two
/// string shapes the protocol uses.
///
/// Every `read*` method throws [MySqlProtocolException] instead of
/// returning a short or default value when the buffer does not have enough
/// bytes left. A truncated packet means the caller's position in the
/// stream is already wrong, and inventing a plausible value would only let
/// it keep going on bad data.
final class ByteReader {
  ByteReader(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  /// How many bytes have been consumed so far.
  int get offset => _offset;

  /// Whether every byte in the buffer has been consumed.
  bool get atEnd => _offset >= _bytes.length;

  void _require(int count) {
    if (_bytes.length - _offset < count) {
      throw MySqlProtocolException(
        'tried to read $count byte(s) at offset $_offset, but only '
        '${_bytes.length - _offset} remain',
      );
    }
  }

  /// Reads a single byte.
  int readUint8() {
    _require(1);
    return _bytes[_offset++];
  }

  /// Reads 2 bytes, least-significant first.
  int readUint16() {
    _require(2);
    final value = _bytes[_offset] | (_bytes[_offset + 1] << 8);
    _offset += 2;
    return value;
  }

  /// Reads 3 bytes, least-significant first. MySQL uses this width for
  /// packet-length headers; there is no built-in 24-bit integer type to
  /// delegate to.
  int readUint24() {
    _require(3);
    final value =
        _bytes[_offset] |
        (_bytes[_offset + 1] << 8) |
        (_bytes[_offset + 2] << 16);
    _offset += 3;
    return value;
  }

  /// Reads 4 bytes, least-significant first, as an unsigned value: the
  /// largest possible result is `4294967295`, never a negative number.
  int readUint32() {
    _require(4);
    final value = ByteData.sublistView(
      _bytes,
      _offset,
      _offset + 4,
    ).getUint32(0, Endian.little);
    _offset += 4;
    return value;
  }

  /// Reads 8 bytes, least-significant first, and hands back exactly what
  /// those bytes mean under a plain two's-complement reading.
  ///
  /// Dart's `int` is signed 64-bit, so a value at or above 2^63 comes back
  /// negative here -- this method does not detect that and correct it.
  /// Whether such a value should be treated as unsigned depends on the
  /// column that produced it (a `BIGINT UNSIGNED` versus a signed
  /// `BIGINT`), which this wire-level reader has no way to know. That
  /// judgment belongs to the value decoder that reads the column's type
  /// alongside the bytes.
  int readUint64() {
    _require(8);
    final value = ByteData.sublistView(
      _bytes,
      _offset,
      _offset + 8,
    ).getInt64(0, Endian.little);
    _offset += 8;
    return value;
  }

  /// Reads a length-encoded integer:
  ///
  /// | first byte | meaning |
  /// |---|---|
  /// | `0x00`-`0xfa` | the value itself (1 byte total) |
  /// | `0xfb` | NULL -- not a value; returns `null` |
  /// | `0xfc` | the following 2 bytes are the value |
  /// | `0xfd` | the following 3 bytes are the value |
  /// | `0xfe` | the following 8 bytes are the value |
  /// | `0xff` | never appears here (it marks an ERR packet) |
  int? readLengthEncodedInt() {
    final marker = readUint8();
    if (marker <= 0xfa) {
      return marker;
    }
    switch (marker) {
      case 0xfb:
        return null;
      case 0xfc:
        return readUint16();
      case 0xfd:
        return readUint24();
      case 0xfe:
        return readUint64();
      default:
        throw MySqlProtocolException(
          'byte 0x${marker.toRadixString(16).padLeft(2, "0")} is not a '
          'valid length-encoded-integer marker',
        );
    }
  }

  /// Reads exactly [count] raw bytes.
  Uint8List readBytes(int count) {
    _require(count);
    final value = Uint8List.sublistView(_bytes, _offset, _offset + count);
    _offset += count;
    return value;
  }

  /// Reads bytes up to the next NUL (`0x00`), decodes them as UTF-8, and
  /// consumes the NUL along with them.
  ///
  /// Throws [MySqlProtocolException] if no NUL remains in the buffer.
  String readNulTerminatedString() {
    final nulAt = _bytes.indexOf(0, _offset);
    if (nulAt == -1) {
      throw MySqlProtocolException(
        'no NUL byte after offset $_offset; the string never ends',
      );
    }
    final value = utf8.decode(_bytes.sublist(_offset, nulAt));
    _offset = nulAt + 1;
    return value;
  }

  /// Reads a length-encoded integer giving a byte count, then that many
  /// bytes decoded as UTF-8. The length is bytes, not characters.
  ///
  /// Returns `null` when the length is the length-encoded-integer NULL
  /// marker (`0xfb`).
  String? readLengthEncodedString() {
    final length = readLengthEncodedInt();
    if (length == null) {
      return null;
    }
    return utf8.decode(readBytes(length));
  }

  /// Reads every byte left in the buffer.
  Uint8List readRemaining() => readBytes(_bytes.length - _offset);

  /// Moves past [count] bytes without decoding them.
  void skip(int count) {
    _require(count);
    _offset += count;
  }
}

/// Writes the same primitives [ByteReader] reads, into a growable buffer.
final class ByteWriter {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  /// Everything written so far.
  Uint8List toBytes() => _builder.toBytes();

  /// Writes a single byte.
  void writeUint8(int v) {
    _builder.addByte(v & 0xff);
  }

  /// Writes 2 bytes, least-significant first.
  void writeUint16(int v) {
    _builder
      ..addByte(v & 0xff)
      ..addByte((v >> 8) & 0xff);
  }

  /// Writes 3 bytes, least-significant first.
  void writeUint24(int v) {
    _builder
      ..addByte(v & 0xff)
      ..addByte((v >> 8) & 0xff)
      ..addByte((v >> 16) & 0xff);
  }

  /// Writes 4 bytes, least-significant first.
  void writeUint32(int v) {
    _builder
      ..addByte(v & 0xff)
      ..addByte((v >> 8) & 0xff)
      ..addByte((v >> 16) & 0xff)
      ..addByte((v >> 24) & 0xff);
  }

  /// Writes 8 bytes, least-significant first, of exactly the two's-
  /// complement bit pattern of [v] -- the inverse of [ByteReader.readUint64],
  /// including for a negative [v] standing in for a value at or above 2^63.
  void writeUint64(int v) {
    final bytes = Uint8List(8);
    ByteData.sublistView(bytes).setInt64(0, v, Endian.little);
    _builder.add(bytes);
  }

  /// Writes [v] as a length-encoded integer, choosing the shortest of the
  /// four forms the format allows (see [ByteReader.readLengthEncodedInt]):
  /// one byte for `0`-`250`, otherwise a marker byte followed by 2, 3 or 8
  /// bytes.
  void writeLengthEncodedInt(int v) {
    if (v < 0) {
      throw ArgumentError.value(
        v,
        'v',
        'length-encoded integers are not negative',
      );
    }
    if (v <= 0xfa) {
      writeUint8(v);
    } else if (v <= 0xffff) {
      writeUint8(0xfc);
      writeUint16(v);
    } else if (v <= 0xffffff) {
      writeUint8(0xfd);
      writeUint24(v);
    } else {
      writeUint8(0xfe);
      writeUint64(v);
    }
  }

  /// Writes raw bytes as-is.
  void writeBytes(List<int> v) {
    _builder.add(v);
  }

  /// Encodes [v] as UTF-8 and writes it followed by a NUL byte.
  void writeNulTerminatedString(String v) {
    writeBytes(utf8.encode(v));
    writeUint8(0);
  }

  /// Encodes [v] as UTF-8 and writes its byte length as a length-encoded
  /// integer, followed by the encoded bytes.
  void writeLengthEncodedString(String v) {
    final bytes = utf8.encode(v);
    writeLengthEncodedInt(bytes.length);
    writeBytes(bytes);
  }

  /// Writes [count] zero bytes.
  void writeZeroes(int count) {
    _builder.add(Uint8List(count));
  }
}
