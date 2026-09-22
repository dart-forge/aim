import 'dart:typed_data';

import 'package:aim_mysql/src/exceptions.dart';
import 'package:aim_mysql/src/protocol/handshake.dart';
import 'package:aim_mysql/src/protocol/packets.dart';
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

  group('a server that refuses the connection before any handshake', () {
    // ER_CON_COUNT_ERROR (1040), ER_HOST_NOT_PRIVILEGED (1130) and
    // ER_HOST_IS_BLOCKED (1129) all arrive this way: an ERR packet where
    // the handshake would otherwise be, before any handshake exists to
    // send at all.
    Uint8List err(int code, String sqlState, String message) =>
        Uint8List.fromList([
          0xff,
          code & 0xff, code >> 8,
          0x23, // '#'
          ...sqlState.codeUnits,
          ...message.codeUnits,
        ]);

    test('is recognised by its leading 0xff', () {
      expect(
        isServerRefusalBeforeHandshake(
          err(1040, '08004', 'Too many connections'),
        ),
        isTrue,
      );
    });

    test('a real handshake is not mistaken for one', () {
      for (final fixture in [handshake84, handshake80]) {
        expect(
          isServerRefusalBeforeHandshake(Uint8List.fromList(fixture)),
          isFalse,
        );
      }
    });

    test('an empty payload is not mistaken for one either', () {
      expect(isServerRefusalBeforeHandshake(Uint8List(0)), isFalse);
    });

    test('building the exception from it carries the real errno and message, '
        'not a bogus protocol version', () {
      final payload = err(1040, '08004', 'Too many connections');

      final exception = mysqlErrorFor(parseCommandPacket(payload) as ErrPacket);

      expect(exception.errorCode, 1040);
      expect(exception.sqlState, '08004');
      expect(exception.message, 'Too many connections');
    });
  });
}
