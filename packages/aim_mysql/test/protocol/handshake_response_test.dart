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

    test('the EOF packet deprecated away, which later layers count on', () {
      // Everything that reads a result set assumes no EOF arrives after the
      // column definitions. If this bit were not asked for, the server
      // would send one, every reader would be a packet out of step, and the
      // connection would desynchronise with nothing to resynchronise
      // against. So this is not a preference — it is a premise the rest of
      // the driver is written on.
      final negotiated = negotiateCapabilities(
        serverHandshake,
        useTls: false,
        withDatabase: false,
      );

      expect(negotiated & Capabilities.deprecateEof, isNot(0));
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

    test('drops a wanted bit the server does not announce', () {
      // The test above cannot fail: the real fixtures announce every bit
      // this driver wants, so the intersection is a no-op against them and
      // deleting the mask entirely would still pass. This one takes a bit
      // away from the server and checks it stops being asked for.
      //
      // multiResults is the right bit to use because it is NOT one of the
      // two the driver refuses outright — protocol41 and ssl are rejected
      // by an explicit throw before the mask is ever reached, so neither
      // exercises the masking at all.
      final withoutMultiResults = _handshakeWithout(Capabilities.multiResults);

      final negotiated = negotiateCapabilities(
        withoutMultiResults,
        useTls: false,
        withDatabase: false,
      );

      expect(negotiated & Capabilities.multiResults, 0);
      expect(
        negotiated & Capabilities.pluginAuth,
        isNot(0),
        reason: 'and the bits the server still has are still asked for',
      );
    });

    test('drops deprecateEof too when the server lacks it', () {
      // Same shape, for the bit whose silent loss is the one this driver
      // cannot survive.
      final negotiated = negotiateCapabilities(
        _handshakeWithout(Capabilities.deprecateEof),
        useTls: false,
        withDatabase: false,
      );

      expect(negotiated & Capabilities.deprecateEof, 0);
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

    test('throws when connectWithDb is set but no database was given', () {
      // The bit alone decides the layout the server will parse. Leaving
      // the field out here while the bit is set would make the server
      // read the very next field -- the auth plugin name -- as the
      // database name instead: a desync with no way back. That makes this
      // a caller mistake, not live data, so it has to be loud rather than
      // silently producing a payload the server will misread.
      final capabilities = negotiateCapabilities(
        serverHandshake,
        useTls: false,
        withDatabase: true,
      );

      expect(
        () => buildHandshakeResponse(
          capabilities: capabilities,
          user: 'test',
          authResponse: Uint8List.fromList(List.filled(20, 0x41)),
          authPluginName: 'caching_sha2_password',
        ),
        throwsArgumentError,
      );
    });

    test('throws when a database was given but connectWithDb is not set', () {
      // The other direction of the same mismatch: a database the caller
      // asked for would otherwise be silently dropped, because the server
      // was never told via the capability bit to expect this field.
      final capabilities = negotiateCapabilities(
        serverHandshake,
        useTls: false,
        withDatabase: false,
      );

      expect(
        () => buildHandshakeResponse(
          capabilities: capabilities,
          user: 'test',
          authResponse: Uint8List.fromList(List.filled(20, 0x41)),
          authPluginName: 'caching_sha2_password',
          database: 'shop',
        ),
        throwsArgumentError,
      );
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
