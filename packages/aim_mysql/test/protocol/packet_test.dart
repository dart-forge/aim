import 'dart:typed_data';

import 'package:aim_mysql/src/protocol/packet.dart';
import 'package:test/test.dart';

Uint8List bytes(int length, {int fill = 0x61}) =>
    Uint8List.fromList(List.filled(length, fill));

void main() {
  group('framing one packet', () {
    test('writes the length little-endian, then the sequence id', () {
      final framed = framePacket(Uint8List.fromList([0x2a]), 0);

      expect(framed, [0x01, 0x00, 0x00, 0x00, 0x2a]);
    });

    test('carries the sequence id it was given', () {
      final framed = framePacket(Uint8List.fromList([0x2a]), 7);

      expect(framed[3], 7);
    });

    test('refuses a payload that needs splitting', () {
      // Splitting is framePackets's job. Silently truncating here would
      // send a packet the server reads as complete when it is not.
      expect(
        () => framePacket(bytes(maxPayloadLength), 0),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('splitting a large payload', () {
    test('a small payload is one packet', () {
      final packets = framePackets(bytes(10), 0);

      expect(packets, hasLength(1));
      expect(packets.single.length, 4 + 10);
    });

    test('a payload one byte over the limit is two packets', () {
      final packets = framePackets(bytes(maxPayloadLength + 1), 0);

      expect(packets, hasLength(2));
      expect(packets[0].length, 4 + maxPayloadLength);
      expect(packets[1].length, 4 + 1);
    });

    test('the sequence id advances across the split', () {
      final packets = framePackets(bytes(maxPayloadLength + 1), 5);

      expect(packets[0][3], 5);
      expect(packets[1][3], 6);
    });

    test('a payload that is exactly the limit ends with an empty packet', () {
      // A packet of exactly 0xffffff means "more follows". Without the empty
      // one the server would wait for a continuation that never comes.
      final packets = framePackets(bytes(maxPayloadLength), 0);

      expect(packets, hasLength(2));
      expect(packets[1].length, 4, reason: 'header only, no payload');
      expect(packets[1].sublist(0, 3), [0x00, 0x00, 0x00]);
    });

    test('a payload that is twice the limit ends with an empty packet too', () {
      final packets = framePackets(bytes(maxPayloadLength * 2), 0);

      expect(packets, hasLength(3));
      expect(packets[2].length, 4);
    });
  });

  group('reassembling', () {
    test('takes a whole packet that arrives at once', () {
      final reassembler = PacketReassembler()
        ..add(framePacket(Uint8List.fromList([0x2a]), 0));

      expect(reassembler.take(), [0x2a]);
    });

    test('answers null until the header has arrived', () {
      final reassembler = PacketReassembler()..add(Uint8List.fromList([0x01]));

      expect(reassembler.take(), isNull);
    });

    test('answers null until the payload has arrived', () {
      final reassembler = PacketReassembler()
        ..add(Uint8List.fromList([0x02, 0x00, 0x00, 0x00, 0x61]));

      expect(reassembler.take(), isNull, reason: 'one byte short');

      reassembler.add(Uint8List.fromList([0x62]));

      expect(reassembler.take(), [0x61, 0x62]);
    });

    test('a packet split across arbitrary chunk boundaries', () {
      // The socket decides where the chunks break, and it does not care
      // about packet boundaries.
      final framed = framePacket(bytes(1000), 0);
      final reassembler = PacketReassembler();

      for (var i = 0; i < framed.length; i++) {
        reassembler.add(Uint8List.sublistView(framed, i, i + 1));
      }

      expect(reassembler.take(), hasLength(1000));
    });

    test('two packets in one chunk come out one at a time', () {
      final reassembler = PacketReassembler()
        ..add(
          Uint8List.fromList([
            ...framePacket(Uint8List.fromList([0x01]), 0),
            ...framePacket(Uint8List.fromList([0x02]), 1),
          ]),
        );

      expect(reassembler.take(), [0x01]);
      expect(reassembler.take(), [0x02]);
      expect(reassembler.take(), isNull);
    });

    test('joins a split payload back into one', () {
      final reassembler = PacketReassembler();
      for (final packet in framePackets(bytes(maxPayloadLength + 10), 0)) {
        reassembler.add(packet);
      }

      expect(reassembler.take(), hasLength(maxPayloadLength + 10));
    });

    test('joins a payload that was exactly the limit', () {
      // The empty terminating packet must not become an empty payload of
      // its own.
      final reassembler = PacketReassembler();
      for (final packet in framePackets(bytes(maxPayloadLength), 0)) {
        reassembler.add(packet);
      }

      expect(reassembler.take(), hasLength(maxPayloadLength));
      expect(reassembler.take(), isNull, reason: 'no extra empty payload');
    });

    test('remembers the sequence id of the packet it returned', () {
      // The next packet the client sends has to continue the sequence, or
      // the server answers with an out-of-order error.
      final reassembler = PacketReassembler()
        ..add(framePacket(Uint8List.fromList([0x2a]), 7));

      reassembler.take();

      expect(reassembler.lastSequenceId, 7);
    });

    test('a split payload reports the sequence id of its last packet', () {
      final reassembler = PacketReassembler();
      for (final packet in framePackets(bytes(maxPayloadLength + 1), 5)) {
        reassembler.add(packet);
      }

      reassembler.take();

      expect(reassembler.lastSequenceId, 6);
    });
  });

  group('buffer aliasing', () {
    // Task 2's review flagged that ByteWriter and ByteReader alias their
    // underlying buffer instead of copying it, for speed. A reassembler is
    // different: it holds bytes across many calls to add(), while whoever
    // is calling it (a socket implementation, for instance) is free to
    // reuse or overwrite its own buffer right after add() returns. This
    // group checks add() does not keep a view onto a buffer it does not
    // own.
    test('add() copies its input, so mutating the source buffer afterwards '
        'does not change what take() returns', () {
      final buffer = Uint8List.fromList([
        0x02, 0x00, 0x00, // 3 of the 4 header bytes: length = 2 so far
        0x00, 0x11, 0x22, // the 4th header byte (sequence id), then payload
      ]);
      final reassembler = PacketReassembler()
        ..add(Uint8List.sublistView(buffer, 0, 3));

      // Clobber the bytes already handed to add(), before add() sees the
      // rest of the packet. A reassembler that aliased instead of copied
      // would read this back as part of the header.
      buffer.fillRange(0, 3, 0xff);

      reassembler.add(Uint8List.sublistView(buffer, 3, 6));

      expect(reassembler.take(), [0x11, 0x22]);
    });
  });

  group('round trip', () {
    test('every size around the split boundary survives', () {
      for (final size in [
        0,
        1,
        maxPayloadLength - 1,
        maxPayloadLength,
        maxPayloadLength + 1,
        maxPayloadLength * 2,
        maxPayloadLength * 2 + 1,
      ]) {
        final reassembler = PacketReassembler();
        for (final packet in framePackets(bytes(size), 0)) {
          reassembler.add(packet);
        }

        expect(reassembler.take(), hasLength(size), reason: 'size $size');
        expect(reassembler.take(), isNull, reason: 'nothing left after $size');
      }
    });
  });
}
