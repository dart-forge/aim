@Tags(['integration'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:aim_mysql/src/protocol/handshake.dart';
import 'package:aim_mysql/src/protocol/packet.dart';
import 'package:rig_mysql/rig_mysql.dart';
import 'package:test/test.dart';

/// Reads the initial handshake off a fresh socket, with nothing but the
/// packet framing in between.
Future<InitialHandshake> handshakeFrom(MySqlLease my) async {
  final socket = await Socket.connect(my.host, my.port);
  final reassembler = PacketReassembler();
  InitialHandshake? parsed;

  await for (final chunk in socket) {
    reassembler.add(Uint8List.fromList(chunk));
    final payload = reassembler.take();
    if (payload != null) {
      parsed = parseInitialHandshake(payload);
      break;
    }
  }
  await socket.close();

  return parsed!;
}

void main() {
  group('8.4', () {
    final my = useMySql(version: '8.4', isolation: MySqlIsolation.none);

    test('sends a handshake this driver can parse', () async {
      final handshake = await handshakeFrom(my);

      expect(handshake.protocolVersion, 0x0a);
      expect(handshake.authPluginData, hasLength(20));
      expect(handshake.authPluginName, 'caching_sha2_password');
    });
  });

  group('8.0', () {
    final my = useMySql(version: '8.0', isolation: MySqlIsolation.none);

    test('sends a handshake this driver can parse', () async {
      final handshake = await handshakeFrom(my);

      expect(handshake.protocolVersion, 0x0a);
      expect(handshake.authPluginData, hasLength(20));
      expect(handshake.authPluginName, 'caching_sha2_password');
    });
  });

  group('native password', () {
    final my = useMySql(
      auth: MySqlAuth.nativePassword,
      isolation: MySqlIsolation.none,
    );

    test('the server still names caching_sha2 in the handshake', () async {
      // The handshake names the server's *default* plugin, not the one this
      // user's password is stored under. The switch to the user's plugin
      // comes as an auth-switch request after the response — which is why
      // the auth layer has to handle that request rather than trusting the
      // handshake.
      final handshake = await handshakeFrom(my);

      expect(handshake.authPluginName, 'caching_sha2_password');
    });
  });
}
