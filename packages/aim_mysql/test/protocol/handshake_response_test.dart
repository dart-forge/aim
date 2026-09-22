import 'dart:typed_data';

import 'package:aim_mysql/src/exceptions.dart';
import 'package:aim_mysql/src/protocol/handshake.dart';
import 'package:aim_mysql/src/protocol/wire.dart';
import 'package:test/test.dart';

import 'handshake_fixtures.dart';

InitialHandshake get serverHandshake =>
    parseInitialHandshake(Uint8List.fromList(handshake84));

void main() {
  group('what this driver asks for', () {
    test('the 4.1 protocol, plugin auth and a secure connection', () {
      final negotiated = negotiateCapabilities(
        serverHandshake,
        useTls: false,
        withDatabase: false,
      );

      expect(negotiated & Capabilities.protocol41, isNot(0));
      expect(negotiated & Capabilities.pluginAuth, isNot(0));
      expect(negotiated & Capabilities.secureConnection, isNot(0));
      expect(negotiated & Capabilities.pluginAuthLenencClientData, isNot(0));
    });

    test('several result sets, because prepared statements need it', () {
      final negotiated = negotiateCapabilities(
        serverHandshake,
        useTls: false,
        withDatabase: false,
      );

      expect(negotiated & Capabilities.multiResults, isNot(0));
    });

    test('never local files', () {
      // Asking would let the server request a file from this process. Not
      // asking is what stops it: the server answers LOAD DATA LOCAL INFILE
      // with an error instead of a request.
      final negotiated = negotiateCapabilities(
        serverHandshake,
        useTls: false,
        withDatabase: false,
      );

      expect(negotiated & Capabilities.localFiles, 0);
    });

    test('never several statements in one call', () {
      final negotiated = negotiateCapabilities(
        serverHandshake,
        useTls: false,
        withDatabase: false,
      );

      expect(negotiated & Capabilities.multiStatements, 0);
    });

    test('TLS only when the caller wants it', () {
      expect(
        negotiateCapabilities(
              serverHandshake,
              useTls: true,
              withDatabase: false,
            ) &
            Capabilities.ssl,
        isNot(0),
      );
      expect(
        negotiateCapabilities(
              serverHandshake,
              useTls: false,
              withDatabase: false,
            ) &
            Capabilities.ssl,
        0,
      );
    });

    test('a database only when one was named', () {
      expect(
        negotiateCapabilities(
              serverHandshake,
              useTls: false,
              withDatabase: true,
            ) &
            Capabilities.connectWithDb,
        isNot(0),
      );
      expect(
        negotiateCapabilities(
              serverHandshake,
              useTls: false,
              withDatabase: false,
            ) &
            Capabilities.connectWithDb,
        0,
      );
    });

    test('nothing the server did not offer', () {
      // Asking for a bit the server does not have makes it close the
      // connection without saying why.
      final negotiated = negotiateCapabilities(
        serverHandshake,
        useTls: true,
        withDatabase: true,
      );

      expect(
        negotiated & ~serverHandshake.capabilities,
        0,
        reason: 'every negotiated bit has to be one the server announced',
      );
    });

    test('refuses a server that cannot do the 4.1 protocol', () {
      // Everything in this driver assumes it, so continuing would produce
      // a confusing failure much later.
      final ancient = _handshakeWithout(Capabilities.protocol41);

      expect(
        () =>
            negotiateCapabilities(ancient, useTls: false, withDatabase: false),
        throwsA(isA<MySqlProtocolException>()),
      );
    });

    test('refuses TLS against a server that does not offer it', () {
      // Better than upgrading into silence: the SSLRequest would be sent
      // and the server would not answer.
      final plaintextOnly = _handshakeWithout(Capabilities.ssl);

      expect(
        () => negotiateCapabilities(
          plaintextOnly,
          useTls: true,
          withDatabase: false,
        ),
        throwsA(isA<MySqlProtocolException>()),
      );
    });

    test('but is happy to stay plaintext against that server', () {
      final plaintextOnly = _handshakeWithout(Capabilities.ssl);

      expect(
        negotiateCapabilities(
          plaintextOnly,
          useTls: false,
          withDatabase: false,
        ),
        isA<int>(),
      );
    });
  });

  group('the response', () {
    Uint8List response({String? database}) => buildHandshakeResponse(
      capabilities: negotiateCapabilities(
        serverHandshake,
        useTls: false,
        withDatabase: database != null,
      ),
      user: 'test',
      authResponse: Uint8List.fromList(List.filled(20, 0x41)),
      authPluginName: 'caching_sha2_password',
      database: database,
    );

    test('opens with the capabilities, the packet size and the charset', () {
      final reader = ByteReader(response());
      final capabilities = reader.readUint32();

      expect(capabilities & Capabilities.protocol41, isNot(0));
      expect(reader.readUint32(), greaterThan(0), reason: 'max packet size');
      expect(reader.readUint8(), greaterThan(0), reason: 'character set');
    });

    test('then 23 zero bytes', () {
      final reader = ByteReader(response());
      reader.skip(9);

      expect(reader.readBytes(23), everyElement(0));
    });

    test('then the user, the auth response and the plugin name', () {
      final reader = ByteReader(response());
      reader.skip(32);

      expect(reader.readNulTerminatedString(), 'test');
      expect(reader.readLengthEncodedString(), hasLength(20));
      expect(reader.readNulTerminatedString(), 'caching_sha2_password');
      expect(reader.atEnd, isTrue);
    });

    test('with the database between them when one was named', () {
      final reader = ByteReader(response(database: 'shop'));
      reader.skip(32);

      expect(reader.readNulTerminatedString(), 'test');
      reader.readLengthEncodedString();
      expect(reader.readNulTerminatedString(), 'shop');
      expect(reader.readNulTerminatedString(), 'caching_sha2_password');
      expect(reader.atEnd, isTrue);
    });

    test('and no database field at all when none was', () {
      // An empty NUL-terminated string is not the same as the field being
      // absent: the server would read the plugin name as the database.
      final reader = ByteReader(response());
      reader.skip(32);
      reader.readNulTerminatedString();
      reader.readLengthEncodedString();

      expect(reader.readNulTerminatedString(), 'caching_sha2_password');
    });

    test('carries an auth response of any length, length-encoded', () {
      // caching_sha2 sends 32 bytes on the fast path, 20 for native
      // password, and the whole password on the TLS full-auth path. A
      // one-byte length field would cap it.
      final built = buildHandshakeResponse(
        capabilities: negotiateCapabilities(
          serverHandshake,
          useTls: false,
          withDatabase: false,
        ),
        user: 'test',
        authResponse: Uint8List.fromList(List.filled(300, 0x41)),
        authPluginName: 'caching_sha2_password',
      );
      final reader = ByteReader(built);
      reader.skip(32);
      reader.readNulTerminatedString();

      expect(reader.readLengthEncodedString(), hasLength(300));
    });
  });

  group('the SSL request', () {
    test('is the first 32 bytes and nothing else', () {
      // Sent before the upgrade, so the server knows to expect TLS. The
      // user name and everything after it goes in the full response, once
      // the socket is encrypted.
      final capabilities = negotiateCapabilities(
        serverHandshake,
        useTls: true,
        withDatabase: false,
      );

      expect(buildSslRequest(capabilities), hasLength(32));
    });

    test('announces the same capabilities the full response will', () {
      // A mismatch makes the server read the encrypted response with the
      // wrong layout.
      final capabilities = negotiateCapabilities(
        serverHandshake,
        useTls: true,
        withDatabase: false,
      );
      final request = ByteReader(buildSslRequest(capabilities));

      expect(request.readUint32(), capabilities);
    });

    test('has the TLS bit set', () {
      final capabilities = negotiateCapabilities(
        serverHandshake,
        useTls: true,
        withDatabase: false,
      );

      expect(
        ByteReader(buildSslRequest(capabilities)).readUint32() &
            Capabilities.ssl,
        isNot(0),
      );
    });
  });
}

/// The captured handshake with [bit] cleared, for the cases a real server
/// will not produce.
InitialHandshake _handshakeWithout(int bit) {
  final original = parseInitialHandshake(Uint8List.fromList(handshake84));
  return InitialHandshake(
    protocolVersion: original.protocolVersion,
    serverVersion: original.serverVersion,
    connectionId: original.connectionId,
    authPluginData: original.authPluginData,
    capabilities: original.capabilities & ~bit,
    characterSet: original.characterSet,
    statusFlags: original.statusFlags,
    authPluginName: original.authPluginName,
  );
}
