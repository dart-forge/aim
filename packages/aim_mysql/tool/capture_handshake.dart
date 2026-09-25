// Prints, as Dart list literals to paste into
// test/protocol/handshake_fixtures.dart:
//
//   - the initial handshake packet a MySQL server sends, the moment the
//     socket opens;
//   - the OK packet that ends a real, successful authentication;
//   - the ERR packet a real server sends for a wrong password.
//
// The handshake needs nothing but a socket, so it is readable before
// anything else in this package has to work -- that is what made it a
// usable anchor for everything built afterwards. The OK and the ERR need a
// real account to authenticate as, which is why capturing them takes a user
// and a password and this driver's own authenticate() to drive the
// exchange, rather than being readable from a bare socket the same way.
//
// Usage: dart run tool/capture_handshake.dart <host> <port> <user> <password>
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:aim_mysql/src/auth/auth.dart';
import 'package:aim_mysql/src/exceptions.dart';
import 'package:aim_mysql/src/protocol/handshake.dart';
import 'package:aim_mysql/src/protocol/packet.dart';

Future<void> main(List<String> args) async {
  if (args.length != 4) {
    stderr.writeln(
      'usage: dart run tool/capture_handshake.dart <host> <port> <user> <password>',
    );
    exit(64);
  }
  final host = args[0];
  final port = int.parse(args[1]);
  final user = args[2];
  final password = args[3];

  final handshakeSocket = await Socket.connect(host, port);
  final handshakeCapture = _Capture(handshakeSocket);
  final handshakePayload = await handshakeCapture.readPacket();
  await handshakeCapture.close();
  _printFixture('handshake', handshakePayload);

  final okPayload = await _captureTerminalAuthPacket(
    host: host,
    port: port,
    user: user,
    password: password,
  );
  _printFixture('ok', okPayload);

  final errPayload = await _captureTerminalAuthPacket(
    host: host,
    port: port,
    user: user,
    // Wrong on purpose, to capture the ERR a real server sends for it.
    password: '$password-wrong-on-purpose',
  );
  _printFixture('err', errPayload);
}

/// Opens a fresh connection, authenticates as [user] with [password], and
/// returns the raw payload of whichever packet ended the exchange: the OK
/// on success, or the ERR authenticate() throws for on a refusal.
///
/// No TLS and no database: neither changes the bytes of the packet this is
/// after, and both would only be another way for this to fail before
/// reaching it.
Future<Uint8List> _captureTerminalAuthPacket({
  required String host,
  required int port,
  required String user,
  required String password,
}) async {
  final socket = await Socket.connect(host, port);
  final capture = _Capture(socket);

  final handshake = parseInitialHandshake(await capture.readPacket());
  capture.nextSequenceId = capture.lastSequenceId + 1;
  final pluginName = handshake.authPluginName;
  if (pluginName == null) {
    throw StateError('the server did not name an authentication plugin');
  }

  final capabilities = negotiateCapabilities(
    handshake,
    useTls: false,
    withDatabase: false,
  );

  try {
    await authenticate(
      transport: capture,
      capabilities: capabilities,
      user: user,
      password: password,
      initialPluginName: pluginName,
      initialScramble: handshake.authPluginData,
    );
  } on MySqlException {
    // Expected for the wrong-password capture; the ERR is already the last
    // entry in capture.received.
  }

  await capture.close();
  return capture.received.last;
}

/// Reads whole MySQL packets off [_socket] one at a time and, as an
/// [AuthTransport], remembers every packet [receive] has returned -- so a
/// caller driving authenticate() over this can look at whichever one
/// turned out to be last: the OK or ERR that ended the exchange.
class _Capture implements AuthTransport {
  _Capture(this._socket) : _iterator = StreamIterator<Uint8List>(_socket);

  final Socket _socket;
  final StreamIterator<Uint8List> _iterator;
  final PacketReassembler _reassembler = PacketReassembler();
  int nextSequenceId = 0;
  final List<Uint8List> received = [];

  @override
  bool get isSecure => false;

  int get lastSequenceId => _reassembler.lastSequenceId;

  /// Reads one whole packet, without recording it -- used for the initial
  /// handshake, which is not part of the [AuthTransport] exchange.
  Future<Uint8List> readPacket() async {
    while (true) {
      final payload = _reassembler.take();
      if (payload != null) return payload;
      if (!await _iterator.moveNext()) {
        throw StateError('the socket closed while a packet was expected');
      }
      _reassembler.add(_iterator.current);
    }
  }

  @override
  Future<void> send(Uint8List payload) async {
    for (final packet in framePackets(payload, nextSequenceId)) {
      _socket.add(packet);
    }
    await _socket.flush();
    nextSequenceId++;
  }

  @override
  Future<Uint8List> receive() async {
    final payload = await readPacket();
    nextSequenceId = lastSequenceId + 1;
    received.add(payload);
    return payload;
  }

  /// Cancels the subscription this capture's [StreamIterator] holds and
  /// destroys the socket. `Socket.close()` alone only half-closes the
  /// write side; leaving the read side subscribed keeps the process alive
  /// waiting for a byte the server will never send.
  Future<void> close() async {
    await _iterator.cancel();
    _socket.destroy();
  }
}

/// Prints [payload] as a `const <name> = <int>[...]` Dart list literal, the
/// same shape handshake_fixtures.dart holds its captures in.
void _printFixture(String name, Uint8List payload) {
  stdout.writeln('// ${payload.length} bytes');
  stdout.writeln('const $name = <int>[');
  for (var i = 0; i < payload.length; i += 12) {
    final row = payload.sublist(i, (i + 12).clamp(0, payload.length));
    stdout.writeln(
      '  ${row.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ')},',
    );
  }
  stdout.writeln('];');
}
