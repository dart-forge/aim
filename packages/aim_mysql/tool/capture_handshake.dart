// Prints the initial handshake packet a MySQL server sends, as a Dart list
// literal to paste into test/protocol/handshake_fixtures.dart.
//
// The server sends this the moment the socket opens, so nothing in this
// package has to work yet for it to be readable. That is what makes it a
// usable anchor for everything above it.
//
// Usage: dart run tool/capture_handshake.dart <host> <port>
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('usage: dart run tool/capture_handshake.dart <host> <port>');
    exit(64);
  }

  final socket = await Socket.connect(args[0], int.parse(args[1]));
  final first = await socket.first;
  await socket.close();

  // The header is four bytes; everything after it is the payload.
  final length = first[0] | (first[1] << 8) | (first[2] << 16);
  stdout.writeln('// sequence id ${first[3]}, payload $length bytes');
  stdout.writeln('const handshake = <int>[');
  for (var i = 4; i < 4 + length; i += 12) {
    final row = first.sublist(i, (i + 12).clamp(0, 4 + length));
    stdout.writeln(
      '  ${row.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ')},',
    );
  }
  stdout.writeln('];');
}
