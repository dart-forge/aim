import 'dart:typed_data';

import 'package:aim_mysql/src/exceptions.dart';
import 'package:aim_mysql/src/protocol/wire.dart';

/// The number of bytes in a packet header: 3 for the length, 1 for the
/// sequence id.
const int _headerLength = 4;

/// The largest payload a single physical packet can carry.
///
/// The header stores the payload length in 3 bytes, so `0xffffff` is the
/// largest value it can hold. That is also the value MySQL reserves to mean
/// "this packet is full; another one follows" -- see [framePackets] for how
/// that ambiguity gets resolved when a payload's length is exactly this or
/// a multiple of it.
const int maxPayloadLength = 0xffffff;

/// Writes the 4-byte header -- 3 bytes of little-endian length, then the
/// 1-byte [sequenceId] -- followed by [payload], with no check on
/// [payload]'s length.
///
/// This is the primitive both [framePacket] and [framePackets] build on.
/// [framePacket] adds a guard on top of it for callers that hand it a
/// whole, unsplit payload; [framePackets] calls this directly, because the
/// chunks it constructs are already known to fit -- including the chunk of
/// exactly [maxPayloadLength] bytes that a full, non-final packet always
/// carries, which is precisely the shape [framePacket]'s guard exists to
/// turn away when it arrives as somebody's whole payload instead.
Uint8List _writePacket(Uint8List payload, int sequenceId) {
  final writer = ByteWriter()
    ..writeUint24(payload.length)
    ..writeUint8(sequenceId)
    ..writeBytes(payload);
  return writer.toBytes();
}

/// Wraps [payload] in the 4-byte packet header: 3 bytes of little-endian
/// length, then the 1-byte [sequenceId].
///
/// Throws [MySqlProtocolException] if [payload] is at or over
/// [maxPayloadLength]. A length that large cannot be told apart, on the
/// wire, from "more follows" (see [framePackets]), so a single packet can
/// never legitimately carry it -- truncating silently here would produce a
/// packet the server reads as complete when it is not. Splitting a payload
/// that size is [framePackets]'s job, not this function's.
Uint8List framePacket(Uint8List payload, int sequenceId) {
  if (payload.length >= maxPayloadLength) {
    throw MySqlProtocolException(
      'payload is ${payload.length} byte(s), at or over the '
      '$maxPayloadLength-byte limit for a single packet; use framePackets '
      'to split it',
    );
  }
  return _writePacket(payload, sequenceId);
}

/// Splits [payload] into as many packets as it takes to carry it, starting
/// at [firstSequenceId] and advancing the sequence id by one per packet.
///
/// Every packet but possibly the last carries exactly [maxPayloadLength]
/// bytes. A payload whose length is a multiple of [maxPayloadLength] --
/// including zero, which still needs one packet, not zero -- ends with a
/// chunk that is itself exactly [maxPayloadLength] bytes, and that chunk
/// alone is indistinguishable from "more follows". So whenever the last
/// chunk written is exactly [maxPayloadLength] bytes, this function appends
/// a further packet with an empty payload, purely to signal the end. A
/// [PacketReassembler] on the other end relies on that empty packet arriving
/// and must not be left waiting for one that a sender omitted.
List<Uint8List> framePackets(Uint8List payload, int firstSequenceId) {
  final packets = <Uint8List>[];
  var offset = 0;
  var sequenceId = firstSequenceId;
  var lastChunkLength = 0;

  // A do/while, not a for-loop over chunks, so that a zero-length payload
  // still produces its one (empty) packet: the loop body always runs at
  // least once, and only then does the `offset < payload.length` check
  // decide whether another chunk is needed.
  do {
    final end = offset + maxPayloadLength < payload.length
        ? offset + maxPayloadLength
        : payload.length;
    final chunk = Uint8List.sublistView(payload, offset, end);
    packets.add(_writePacket(chunk, sequenceId));
    lastChunkLength = chunk.length;
    sequenceId++;
    offset = end;
  } while (offset < payload.length);

  if (lastChunkLength == maxPayloadLength) {
    packets.add(_writePacket(Uint8List(0), sequenceId));
  }

  return packets;
}

/// One logical packet [PacketReassembler] has finished assembling: its
/// payload, plus the sequence id of the last physical packet that made it
/// up (see [PacketReassembler.lastSequenceId]).
class _CompletedPacket {
  _CompletedPacket(this.payload, this.sequenceId);

  final Uint8List payload;
  final int sequenceId;
}

/// Reassembles the packets [framePacket] and [framePackets] produce back
/// into logical payloads, from bytes that arrive in whatever grouping the
/// transport happens to deliver: one byte at a time, several packets at
/// once, or a single packet split across many calls to [add]. A socket's
/// read events don't align with packet boundaries, so this class does not
/// assume they do.
///
/// A run of physical packets whose length is exactly [maxPayloadLength]
/// means "more follows"; the logical packet is only complete once a
/// physical packet shorter than that arrives (including a length of zero,
/// the empty packet [framePackets] appends after a payload that was itself
/// an exact multiple of [maxPayloadLength]). This class concatenates those
/// physical payloads back into the single logical payload [take] hands
/// back, so a caller downstream never has to know a payload was split.
///
/// **On aliasing:** [ByteWriter] and [ByteReader] (see `wire.dart`)
/// deliberately alias their underlying buffer instead of copying it, for
/// speed -- reasonable there, because both are used and discarded within a
/// single call. This class is different: it holds bytes across many calls
/// to [add], while a caller (a socket implementation, for instance) is free
/// to reuse or overwrite its own buffer the moment [add] returns. So [add]
/// copies every byte of [chunk] into storage this class owns before doing
/// anything else with it. That copy is an extra pass over the bytes, but
/// the alternative -- a payload that silently changes after [take] already
/// handed it out -- is worse, especially in a protocol with no
/// resynchronisation point to recover with once the stream is misread.
final class PacketReassembler {
  /// Bytes that have arrived but have not yet been folded into
  /// [_currentPayload]: either fewer than [_headerLength] bytes, or a
  /// header plus a partial payload. Always a copy -- see the class doc
  /// comment on [add] -- and never aliased by anything handed to [add].
  final BytesBuilder _pending = BytesBuilder();

  /// The payload bytes of the logical packet currently being assembled:
  /// the physical packets seen so far whose length was exactly
  /// [maxPayloadLength], meaning more were expected to follow.
  final BytesBuilder _currentPayload = BytesBuilder();

  /// Logical packets that are complete and waiting for [take], in the
  /// order they finished.
  final List<_CompletedPacket> _completed = [];

  int _lastSequenceId = 0;

  /// Adds [chunk] -- any number of bytes, from any point in the packet
  /// stream -- and assembles as many complete logical packets out of the
  /// bytes accumulated so far as it can.
  ///
  /// Copies [chunk] before doing anything else with it; see the class doc
  /// comment.
  void add(Uint8List chunk) {
    _pending.add(chunk);
    _drain();
  }

  /// Returns the payload of the next logical packet that has fully
  /// arrived, or `null` if none has.
  ///
  /// Packets come out in the order they completed, one per call: a second
  /// call right after a first that returned a payload gets the next one,
  /// not the same one again.
  Uint8List? take() {
    if (_completed.isEmpty) {
      return null;
    }
    final packet = _completed.removeAt(0);
    _lastSequenceId = packet.sequenceId;
    return packet.payload;
  }

  /// The sequence id of the last physical packet of the logical packet
  /// [take] most recently returned. `0` if [take] has never returned one.
  int get lastSequenceId => _lastSequenceId;

  /// Consumes as many complete physical packets as [_pending] currently
  /// holds, folding each one's payload into [_currentPayload], and moves
  /// [_currentPayload] into [_completed] whenever a physical packet
  /// shorter than [maxPayloadLength] shows that the logical packet just
  /// ended.
  void _drain() {
    while (true) {
      final available = _pending.toBytes();
      if (available.length < _headerLength) {
        return;
      }

      final reader = ByteReader(available);
      final length = reader.readUint24();
      final sequenceId = reader.readUint8();
      if (available.length - _headerLength < length) {
        return;
      }

      final payload = reader.readBytes(length);
      _currentPayload.add(payload);

      final consumed = _headerLength + length;
      _pending.clear();
      if (available.length > consumed) {
        _pending.add(Uint8List.sublistView(available, consumed));
      }

      if (length < maxPayloadLength) {
        _completed.add(_CompletedPacket(_currentPayload.toBytes(), sequenceId));
        _currentPayload.clear();
      }
    }
  }
}
