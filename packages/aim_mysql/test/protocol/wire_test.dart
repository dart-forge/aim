import 'dart:typed_data';

import 'package:aim_mysql/src/exceptions.dart';
import 'package:aim_mysql/src/protocol/wire.dart';
import 'package:test/test.dart';

ByteReader readerOf(List<int> bytes) => ByteReader(Uint8List.fromList(bytes));

void main() {
  group('fixed-width integers are little-endian', () {
    test('uint8', () {
      expect(readerOf([0x2a]).readUint8(), 42);
    });

    test('uint16', () {
      // 0x0102 arrives as 02 01.
      expect(readerOf([0x02, 0x01]).readUint16(), 0x0102);
    });

    test('uint24', () {
      expect(readerOf([0x03, 0x02, 0x01]).readUint24(), 0x010203);
    });

    test('uint32', () {
      expect(readerOf([0x04, 0x03, 0x02, 0x01]).readUint32(), 0x01020304);
    });

    test('uint64', () {
      expect(
        readerOf([0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01]).readUint64(),
        0x0102030405060708,
      );
    });

    test('the largest uint32 is not read as negative', () {
      expect(readerOf([0xff, 0xff, 0xff, 0xff]).readUint32(), 4294967295);
    });
  });

  group('length-encoded integers', () {
    test('a single byte below the markers is the value itself', () {
      expect(readerOf([0x00]).readLengthEncodedInt(), 0);
      expect(readerOf([0xfa]).readLengthEncodedInt(), 250);
    });

    test('0xfb is null, not a value', () {
      // This is how a NULL column arrives in a text-protocol row and how an
      // absent string arrives in several packets. Returning 0 would be a
      // value the server never sent.
      expect(readerOf([0xfb]).readLengthEncodedInt(), isNull);
    });

    test('0xfc takes the next two bytes', () {
      expect(readerOf([0xfc, 0x02, 0x01]).readLengthEncodedInt(), 0x0102);
    });

    test('0xfd takes the next three', () {
      expect(
        readerOf([0xfd, 0x03, 0x02, 0x01]).readLengthEncodedInt(),
        0x010203,
      );
    });

    test('0xfe takes the next eight', () {
      expect(
        readerOf([0xfe, 0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01])
            .readLengthEncodedInt(),
        0x0102030405060708,
      );
    });

    test('0xff is not a valid marker', () {
      // The table in readLengthEncodedInt's own doc comment lists exactly
      // five meanings for the leading byte; 0xff is reserved for an ERR
      // packet and never legitimately starts a length-encoded integer.
      // Every byte 0x00-0xfa is a value in its own right (handled above),
      // so this is the one input that has to fall through to the
      // "nothing else is valid" branch.
      expect(
        () => readerOf([0xff]).readLengthEncodedInt(),
        throwsA(isA<MySqlProtocolException>()),
      );
    });

    test('consumes exactly the bytes the marker claims', () {
      final reader = readerOf([0xfc, 0x02, 0x01, 0x2a]);

      expect(reader.readLengthEncodedInt(), 0x0102);
      expect(reader.readUint8(), 42, reason: 'the marker plus two, no more');
    });
  });

  group('strings', () {
    test('a NUL-terminated string stops at the NUL and consumes it', () {
      final reader = readerOf([0x61, 0x62, 0x00, 0x2a]);

      expect(reader.readNulTerminatedString(), 'ab');
      expect(reader.readUint8(), 42);
    });

    test('a NUL-terminated string can be empty', () {
      expect(readerOf([0x00]).readNulTerminatedString(), '');
    });

    test('a length-encoded string reads that many bytes', () {
      final reader = readerOf([0x02, 0x61, 0x62, 0x2a]);

      expect(reader.readLengthEncodedString(), 'ab');
      expect(reader.readUint8(), 42);
    });

    test('a length-encoded string of 0xfb is null', () {
      expect(readerOf([0xfb]).readLengthEncodedString(), isNull);
    });

    test('decodes as UTF-8', () {
      // The connection asks for utf8mb4, so every string the server sends is
      // UTF-8. Reading it as Latin-1 would corrupt anything non-ASCII in a
      // table name or an error message.
      expect(readerOf([0x03, 0xe6, 0x97, 0xa5]).readLengthEncodedString(), '日');
    });
  });

  group('reading past the end', () {
    test('throws rather than returning a short or zero value', () {
      // A truncated packet means the stream is out of step. Answering with
      // a plausible value would let the caller act on invented data.
      expect(
        () => readerOf([0x01]).readUint16(),
        throwsA(isA<MySqlProtocolException>()),
      );
      expect(
        () => readerOf([]).readUint8(),
        throwsA(isA<MySqlProtocolException>()),
      );
      expect(
        () => readerOf([0xfc, 0x01]).readLengthEncodedInt(),
        throwsA(isA<MySqlProtocolException>()),
      );
      expect(
        () => readerOf([0x61, 0x62]).readNulTerminatedString(),
        throwsA(isA<MySqlProtocolException>()),
        reason: 'no NUL in sight',
      );
    });
  });

  group(
    'every misread surfaces as MySqlProtocolException, not a lower-level type',
    () {
      test(
        'invalid UTF-8 in a NUL-terminated string throws, not FormatException',
        () {
          // 0xc3 is a lead byte for a two-byte sequence; the NUL right after it
          // means the read itself is not short, only the encoding is broken.
          expect(
            () => readerOf([0xc3, 0x00]).readNulTerminatedString(),
            throwsA(isA<MySqlProtocolException>()),
          );
        },
      );

      test(
        'invalid UTF-8 in a length-encoded string throws, not FormatException',
        () {
          // 0xff and 0xfe never appear in valid UTF-8. Both bytes the length
          // promised are present, so this is not a short read either.
          expect(
            () => readerOf([0x02, 0xff, 0xfe]).readLengthEncodedString(),
            throwsA(isA<MySqlProtocolException>()),
          );
        },
      );

      test('a length-encoded integer at or above 2^63 throws rather than going negative', () {
        // 0xfe followed by eight bytes worth exactly 2^63. readUint64 hands
        // that back as a negative int, and nothing reading a length or count
        // off the wire should ever treat a negative result as valid.
        final bytes = [0xfe, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80];

        expect(
          () => readerOf(bytes).readLengthEncodedInt(),
          throwsA(isA<MySqlProtocolException>()),
        );
      });

      test('a length-encoded string whose length is at or above 2^63 throws, not RangeError', () {
        // Without a guard on the decoded length, this reaches
        // Uint8List.sublistView with an end offset before its start and
        // RangeError escapes instead of this driver's own exception type.
        final bytes = [0xfe, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80];

        expect(
          () => readerOf(bytes).readLengthEncodedString(),
          throwsA(isA<MySqlProtocolException>()),
        );
      });
    },
  );

  group('offset and remaining', () {
    test('offset follows what has been read', () {
      final reader = readerOf([0x01, 0x02, 0x03]);

      expect(reader.offset, 0);
      reader.readUint8();
      expect(reader.offset, 1);
      reader.readUint16();
      expect(reader.offset, 3);
      expect(reader.atEnd, isTrue);
    });

    test('readRemaining takes everything left', () {
      final reader = readerOf([0x01, 0x02, 0x03]);
      reader.readUint8();

      expect(reader.readRemaining(), [0x02, 0x03]);
      expect(reader.atEnd, isTrue);
    });

    test('skip moves past bytes without reading them', () {
      final reader = readerOf([0x01, 0x02, 0x2a]);
      reader.skip(2);

      expect(reader.readUint8(), 42);
    });
  });

  group('the writer is the reader inverted', () {
    test('every fixed-width integer round-trips', () {
      final writer = ByteWriter()
        ..writeUint8(42)
        ..writeUint16(0x0102)
        ..writeUint24(0x010203)
        ..writeUint32(0x01020304)
        ..writeUint64(0x0102030405060708);

      final reader = ByteReader(writer.toBytes());

      expect(reader.readUint8(), 42);
      expect(reader.readUint16(), 0x0102);
      expect(reader.readUint24(), 0x010203);
      expect(reader.readUint32(), 0x01020304);
      expect(reader.readUint64(), 0x0102030405060708);
      expect(reader.atEnd, isTrue);
    });

    test('every length-encoded integer round-trips, across each marker', () {
      // The boundaries are where an off-by-one in the marker choice shows
      // up: 250 is one byte, 251 needs 0xfc.
      for (final value in [0, 1, 250, 251, 65535, 65536, 16777215, 16777216]) {
        final writer = ByteWriter()..writeLengthEncodedInt(value);
        final reader = ByteReader(writer.toBytes());

        expect(
          reader.readLengthEncodedInt(),
          value,
          reason: 'round trip of $value',
        );
        expect(reader.atEnd, isTrue, reason: 'no slack after $value');
      }
    });

    test('writeLengthEncodedInt refuses a negative value', () {
      // Every marker in the format describes a byte count or a value to
      // follow, and none of them can stand for "negative" -- writing one
      // anyway would produce bytes readLengthEncodedInt was never meant to
      // read back.
      expect(() => ByteWriter().writeLengthEncodedInt(-1), throwsArgumentError);
    });

    test('strings round-trip', () {
      final writer = ByteWriter()
        ..writeNulTerminatedString('ab')
        ..writeLengthEncodedString('日本語');

      final reader = ByteReader(writer.toBytes());

      expect(reader.readNulTerminatedString(), 'ab');
      expect(reader.readLengthEncodedString(), '日本語');
      expect(reader.atEnd, isTrue);
    });

    test('a length-encoded string counts bytes, not characters', () {
      // Three characters, nine bytes. Writing 3 as the length would cut the
      // first character in the middle.
      final writer = ByteWriter()..writeLengthEncodedString('日本語');

      expect(writer.toBytes()[0], 9);
    });

    test('writeZeroes writes exactly that many', () {
      expect(ByteWriter().let((w) => w..writeZeroes(3)).toBytes(), [0, 0, 0]);
    });
  });
}

/// Small helper so a cascade can be used inside an expression above.
extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
