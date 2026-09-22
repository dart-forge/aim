import 'dart:typed_data';

import 'package:aim_mysql/src/exceptions.dart';
import 'package:aim_mysql/src/protocol/handshake.dart';
import 'package:test/test.dart';

import 'handshake_fixtures.dart';

void main() {
  for (final (label, fixture) in [('8.4', handshake84), ('8.0', handshake80)]) {
    group('the handshake a real $label server sent', () {
      late InitialHandshake handshake;

      setUp(() {
        handshake = parseInitialHandshake(Uint8List.fromList(fixture));
      });

      test('is protocol version 10', () {
        expect(handshake.protocolVersion, 0x0a);
      });

      test('names a server version this driver supports', () {
        // Not parsed for behaviour — nothing branches on it — but a
        // fixture captured from the wrong server would show up here.
        expect(handshake.serverVersion, startsWith(label));
      });

      test('carries a connection id', () {
        expect(handshake.connectionId, greaterThan(0));
      });

      test('asks for a plugin this driver implements', () {
        expect(
          handshake.authPluginName,
          anyOf('caching_sha2_password', 'mysql_native_password'),
        );
      });

      test('carries exactly 20 bytes of scramble', () {
        // Every authentication plugin hashes against this. 21 would mean
        // the trailing NUL of the second part was kept; 19 or 8 would mean
        // the two parts were not joined.
        expect(handshake.authPluginData, hasLength(20));
      });

      test('the scramble has no NUL in it', () {
        // The second part arrives NUL-terminated and the terminator is not
        // part of the scramble. A NUL here means it was kept.
        expect(handshake.authPluginData, isNot(contains(0)));
      });

      test('announces the capabilities this driver needs', () {
        expect(
          handshake.capabilities & Capabilities.protocol41,
          isNot(0),
          reason: 'the 4.1 protocol is not optional here',
        );
        expect(handshake.capabilities & Capabilities.pluginAuth, isNot(0));
        expect(
          handshake.capabilities & Capabilities.secureConnection,
          isNot(0),
        );
      });

      test('offers TLS', () {
        // Both supported versions generate a certificate at initialisation,
        // so a server without this is either configured to refuse TLS or is
        // not one of them.
        expect(handshake.capabilities & Capabilities.ssl, isNot(0));
      });

      test('consumes the whole payload', () {
        // A parser that stops early looks correct on every field it reads
        // and silently ignores the rest. Anything left over means the
        // layout is not what this parser thinks.
        expect(
          () => parseInitialHandshake(Uint8List.fromList([...fixture, 0x2a])),
          throwsA(isA<MySqlProtocolException>()),
          reason: 'one byte too many has to be noticed',
        );
      });
    });
  }

  group('a handshake this driver cannot use', () {
    test('an older protocol version is refused', () {
      // Protocol 9 has a different layout entirely. Reading it as 10 would
      // produce nonsense that looks like data.
      final ninth = Uint8List.fromList([0x09, ...handshake84.skip(1)]);

      expect(
        () => parseInitialHandshake(ninth),
        throwsA(isA<MySqlProtocolException>()),
      );
    });

    test('and the message says what was found', () {
      final ninth = Uint8List.fromList([0x09, ...handshake84.skip(1)]);

      expect(
        () => parseInitialHandshake(ninth),
        throwsA(
          isA<MySqlProtocolException>().having(
            (e) => e.toString(),
            'message',
            contains('9'),
          ),
        ),
      );
    });
  });
}
