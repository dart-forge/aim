import 'dart:typed_data';

import 'package:aim_mysql/src/exceptions.dart';
import 'package:aim_mysql/src/protocol/packet.dart';
import 'package:aim_mysql/src/protocol/wire.dart';

/// The only protocol version this driver understands.
///
/// Protocol 9 exists but uses a different, older layout entirely; nothing
/// here can make sense of it.
const int _protocolVersion10 = 0x0a;

/// The auth-plugin-data comes in two parts. The first is always this many
/// bytes; see [InitialHandshake] for how the second is sized.
const int _authPluginDataPart1Length = 8;

/// Bytes reserved by the protocol between the auth-plugin-data length and
/// its second part. Always zero; this driver does not check that, since
/// nothing here depends on it staying zero.
const int _reservedLength = 10;

/// The capability bits this driver negotiates or checks.
///
/// Only the ones with a reason to be named are here. The full set is much
/// larger and most of it never comes up.
abstract final class Capabilities {
  /// A database is named in the handshake response.
  static const int connectWithDb = 0x00000008;

  /// The server may ask the client to send it a local file. **This driver
  /// never asks for this.** Not asking is what stops the server from
  /// requesting one — a request the client would either have to answer,
  /// opening a hole a malicious server could read files through, or ignore,
  /// which desynchronises the stream.
  static const int localFiles = 0x00000080;

  /// The 4.1 protocol. Everything in this driver assumes it.
  static const int protocol41 = 0x00000200;

  /// The server will speak TLS if the client asks.
  static const int ssl = 0x00000800;

  /// A single call may carry several statements. **This driver never asks
  /// for this**, so the server refuses them.
  static const int multiStatements = 0x00010000;

  /// A statement may return more than one result set. Required for
  /// prepared statements, so this driver asks for it.
  static const int multiResults = 0x00020000;

  /// The handshake names which authentication plugin to use.
  static const int pluginAuth = 0x00080000;

  /// The auth response in the handshake response is length-encoded.
  static const int pluginAuthLenencClientData = 0x00200000;

  /// The 4.1 authentication handshake, which is what the scramble is for.
  static const int secureConnection = 0x00008000;

  /// An EOF packet is replaced by an OK packet at the end of a result set.
  /// This driver asks for it: one shape to parse instead of two.
  static const int deprecateEof = 0x01000000;
}

/// The first packet a MySQL server sends, the moment the socket opens.
///
/// Carries the server's identity, the scramble this driver's authentication
/// response is built from, and which capabilities and authentication plugin
/// the server offers.
final class InitialHandshake {
  InitialHandshake({
    required this.protocolVersion,
    required this.serverVersion,
    required this.connectionId,
    required this.authPluginData,
    required this.capabilities,
    required this.characterSet,
    required this.statusFlags,
    required this.authPluginName,
  });

  /// Always `0x0a` -- [parseInitialHandshake] throws rather than hand back
  /// any other value.
  final int protocolVersion;

  /// The server's version string, e.g. `8.4.11`. Not parsed further:
  /// nothing in this driver branches on it.
  final String serverVersion;

  /// The id the server assigned this connection.
  final int connectionId;

  /// The scramble this connection's authentication response is hashed
  /// against. Always 20 bytes: the two halves the wire sends separately,
  /// joined, with the second half's trailing NUL dropped.
  final Uint8List authPluginData;

  /// The capability flags the server offers, as a single 32-bit value
  /// combining the lower and upper halves the wire sends separately. Test
  /// a bit with [Capabilities].
  final int capabilities;

  /// The server's default character set, as its protocol id.
  final int characterSet;

  /// The server's status flags at connection time (e.g. autocommit).
  final int statusFlags;

  /// The authentication plugin the server wants used, or `null` if
  /// [Capabilities.pluginAuth] is not set.
  final String? authPluginName;
}

/// Whether [payload] -- the very first packet a server sends, right after
/// the socket opens -- is the server refusing the connection outright
/// rather than beginning a handshake at all.
///
/// A real server sends an ERR packet here instead of a handshake for
/// `ER_CON_COUNT_ERROR` (1040), `ER_HOST_NOT_PRIVILEGED` (1130) and
/// `ER_HOST_IS_BLOCKED` (1129) among others -- the most common connection
/// failures there are. Handing that payload to [parseInitialHandshake]
/// instead reads its `0xff` marker byte as a bogus protocol version and
/// throws [MySqlProtocolException], discarding the errno, the SQLSTATE and
/// the server's own message that a real [MySqlException] would have
/// carried. [MySqlConnection.connect] checks this first and raises that
/// instead.
///
/// Public (though not exported from the package barrel) specifically so
/// this byte-level decision has its own unit test with a hand-built ERR
/// payload -- the same reason [buildExecutePayload] is public in
/// `statement.dart`.
bool isServerRefusalBeforeHandshake(Uint8List payload) =>
    payload.isNotEmpty && payload[0] == 0xff;

/// Parses the initial handshake packet's payload -- everything after the
/// 4-byte packet header, not including it.
///
/// Throws [MySqlProtocolException] if the protocol version is not `0x0a`,
/// if the payload runs out of bytes before a field the layout promises, or
/// if bytes remain after every field has been read. That last check matters
/// as much as any of the field reads: a parser that stops early looks
/// correct on every field it does read and silently drops the rest, so a
/// mistake in the layout would otherwise go unnoticed.
InitialHandshake parseInitialHandshake(Uint8List payload) {
  final reader = ByteReader(payload);

  final protocolVersion = reader.readUint8();
  if (protocolVersion != _protocolVersion10) {
    throw MySqlProtocolException(
      'unsupported protocol version $protocolVersion; this driver only '
      'speaks protocol $_protocolVersion10',
    );
  }

  final serverVersion = reader.readNulTerminatedString();
  final connectionId = reader.readUint32();
  final authPluginDataPart1 = reader.readBytes(_authPluginDataPart1Length);

  reader.skip(1); // filler, always 0x00.

  final capabilitiesLower = reader.readUint16();
  final characterSet = reader.readUint8();
  final statusFlags = reader.readUint16();
  final capabilitiesUpper = reader.readUint16();
  final capabilities = capabilitiesLower | (capabilitiesUpper << 16);

  final authPluginDataLength = reader.readUint8();

  reader.skip(_reservedLength);

  // The second part is padded out to at least 13 bytes even when the
  // reported length is shorter, and its last byte is always a NUL
  // terminator that is not part of the scramble.
  final authPluginDataPart2Length =
      authPluginDataLength - _authPluginDataPart1Length < 13
      ? 13
      : authPluginDataLength - _authPluginDataPart1Length;
  final authPluginDataPart2 = reader.readBytes(authPluginDataPart2Length);
  final authPluginData = Uint8List.fromList([
    ...authPluginDataPart1,
    ...authPluginDataPart2.sublist(0, authPluginDataPart2.length - 1),
  ]);

  final authPluginName = (capabilities & Capabilities.pluginAuth) != 0
      ? reader.readNulTerminatedString()
      : null;

  if (!reader.atEnd) {
    throw MySqlProtocolException(
      'handshake payload had bytes left over after every known field was '
      'read: read ${reader.offset} of ${payload.length} byte(s)',
    );
  }

  return InitialHandshake(
    protocolVersion: protocolVersion,
    serverVersion: serverVersion,
    connectionId: connectionId,
    authPluginData: authPluginData,
    capabilities: capabilities,
    characterSet: characterSet,
    statusFlags: statusFlags,
    authPluginName: authPluginName,
  );
}

/// The character set this driver announces about itself in the handshake
/// response: `utf8mb4_general_ci`.
///
/// The servers this driver targets announce `utf8mb4_0900_ai_ci` (255) in
/// their own handshake -- see the fixtures in `handshake_fixtures.dart` --
/// and matching it back to them is tempting. Don't: this field says what
/// encoding the *client* used for the bytes it is about to send, not
/// anything about the server, and it is not the collation later
/// comparisons and sorts run under either -- that is a property of the
/// table and column involved, chosen independently of this handshake.
/// `utf8mb4_general_ci` (45) is supported on both 8.0 and 8.4, so this one
/// value covers every server this driver targets with no need to branch on
/// which version is on the other end -- and nothing else in this driver
/// parses the server's version string to decide behaviour either, so this
/// field would be the odd one out if it did.
const int _clientCharacterSet = 45;

/// Decides which capabilities this driver asks for against [handshake]:
/// what this driver always wants, adjusted by [useTls] and [withDatabase],
/// intersected with what the server actually announced.
///
/// The intersection matters as much as the wish list: asking for a bit the
/// server never announced makes it close the connection without saying
/// why, so nothing this driver wants is allowed through unless
/// [handshake.capabilities] offered it first.
///
/// [Capabilities.localFiles] and [Capabilities.multiStatements] are never
/// on the wish list, so they never appear in the result even when the
/// server offers them. Local files would let the server ask this process
/// to read and hand back an arbitrary file on disk; not asking for the
/// capability is what makes the server answer a `LOAD DATA LOCAL INFILE`
/// statement with an error instead of that request. Multiple statements
/// per call would open a path this driver has no way to return results
/// for -- it reads one result set per call, not a sequence of them. Both
/// exclusions have tests asserting the bit stays clear; those tests are
/// what enforces this, not a description of intent the code is free to
/// drift away from later.
///
/// Throws [MySqlProtocolException] if [handshake] did not announce
/// [Capabilities.protocol41]: everything else this driver does assumes
/// the 4.1 protocol, so continuing would only turn one clear problem into
/// a confusing failure much later. Also throws it if [useTls] is true but
/// [handshake] did not announce [Capabilities.ssl] -- better to say so now
/// than to send an SSLRequest a server that never offered TLS will not
/// answer. Also throws it if [Capabilities.deprecateEof] does not survive
/// the intersection with what [handshake] announced: every reader of a
/// result set in this driver assumes the server never sends a legacy EOF
/// packet, and against a server that does not grant this, it would
/// proceed anyway and desynchronise permanently on the first one.
int negotiateCapabilities(
  InitialHandshake handshake, {
  required bool useTls,
  required bool withDatabase,
}) {
  if (handshake.capabilities & Capabilities.protocol41 == 0) {
    throw MySqlProtocolException(
      'server did not announce the protocol41 capability; this driver '
      'only speaks the 4.1 protocol and cannot negotiate a connection '
      'with a server that does not offer it',
    );
  }
  if (useTls && handshake.capabilities & Capabilities.ssl == 0) {
    throw MySqlProtocolException(
      'TLS was requested but the server did not announce the ssl '
      'capability; it would not answer an SSLRequest',
    );
  }

  // Capabilities.localFiles and Capabilities.multiStatements are not in
  // this list on purpose -- see this function's doc comment above -- and
  // the tests named after them are what keeps that true, not this comment.
  var wanted =
      Capabilities.protocol41 |
      Capabilities.secureConnection |
      Capabilities.pluginAuth |
      Capabilities.pluginAuthLenencClientData |
      Capabilities.multiResults |
      Capabilities.deprecateEof;

  if (useTls) {
    wanted |= Capabilities.ssl;
  }
  if (withDatabase) {
    wanted |= Capabilities.connectWithDb;
  }

  final negotiated = wanted & handshake.capabilities;
  if (negotiated & Capabilities.deprecateEof == 0) {
    // Asking is not enough: negotiateCapabilities only ever grants a bit
    // the server actually announced (see this function's own doc
    // comment), so a server that never offers deprecateEof would
    // otherwise silently fall out of the wish list here, and every
    // result-set reader downstream assumes it never happens.
    throw MySqlProtocolException(
      'server did not announce the deprecateEof capability; this driver '
      'reads every result set assuming no legacy EOF packet arrives, and '
      'cannot function without it',
    );
  }
  return negotiated;
}

/// Writes the 32 bytes [buildHandshakeResponse] and [buildSslRequest]
/// both start with: [capabilities], the max packet length this driver
/// will receive, the character set, and 23 zero-filled padding bytes.
void _writeHandshakeHeader(ByteWriter writer, int capabilities) {
  writer
    ..writeUint32(capabilities)
    ..writeUint32(maxPayloadLength)
    ..writeUint8(_clientCharacterSet)
    ..writeZeroes(23);
}

/// Builds the handshake response packet's payload for the already-
/// negotiated [capabilities] (see [negotiateCapabilities]).
///
/// The layout, in order:
///
/// | | |
/// |---|---|
/// | 4 bytes | [capabilities] |
/// | 4 bytes | the max packet length this driver will receive |
/// | 1 byte | the character set |
/// | 23 bytes | padding, all zero |
/// | NUL-terminated | [user] |
/// | length-encoded | [authResponse] |
/// | NUL-terminated | [database], only when [Capabilities.connectWithDb] is set |
/// | NUL-terminated | [authPluginName], only when [Capabilities.pluginAuth] is set |
///
/// Whether the database field is written is decided by the
/// [Capabilities.connectWithDb] bit in [capabilities] alone, never by
/// whether [database] happens to be null. The server decides how to read
/// this payload from that bit, so [database] has to agree with it: throws
/// [ArgumentError] if it does not. The bit set with [database] null would
/// leave the field simply missing, so the server would read the very next
/// field -- the auth plugin name -- as the database name instead; the bit
/// clear with [database] non-null would silently drop a database the
/// caller asked for. Either way is a wire desync with no resynchronisation
/// point once it happens, so this is not checked softly. The intended call
/// shape --
/// `negotiateCapabilities(withDatabase: database != null)` feeding
/// straight into this [database] parameter -- can never disagree, which is
/// why a disagreement here is always a caller mistake and not live server
/// data, and so [ArgumentError] rather than [MySqlProtocolException].
///
/// [authResponse] is written as the raw bytes it is, not as text: it is a
/// password hash, not necessarily valid UTF-8, so it cannot go through
/// the same UTF-8 encoding step [user], [database] and [authPluginName]
/// do. It is length-encoded rather than given a single length byte
/// because [Capabilities.pluginAuthLenencClientData] is always among the
/// capabilities this driver asks for, and a single byte could not hold
/// every length an authentication plugin might produce -- `caching_sha2`
/// alone sends 32 bytes on its fast path and the whole password, unhashed,
/// on its full-auth path.
Uint8List buildHandshakeResponse({
  required int capabilities,
  required String user,
  required Uint8List authResponse,
  required String authPluginName,
  String? database,
}) {
  final writer = ByteWriter();
  _writeHandshakeHeader(writer, capabilities);
  writer
    ..writeNulTerminatedString(user)
    ..writeLengthEncodedInt(authResponse.length)
    ..writeBytes(authResponse);

  final wantsDatabase = (capabilities & Capabilities.connectWithDb) != 0;
  if (wantsDatabase && database == null) {
    throw ArgumentError.value(
      database,
      'database',
      'capabilities has connectWithDb set, so the server expects a '
          'database name in this field, but null was given',
    );
  }
  if (!wantsDatabase && database != null) {
    throw ArgumentError.value(
      database,
      'database',
      'capabilities does not have connectWithDb set, so the server does '
          'not expect a database name in this field',
    );
  }
  if (wantsDatabase) {
    writer.writeNulTerminatedString(database!);
  }
  if ((capabilities & Capabilities.pluginAuth) != 0) {
    writer.writeNulTerminatedString(authPluginName);
  }

  return writer.toBytes();
}

/// Builds the SSLRequest packet's payload: the first 32 bytes of what
/// [buildHandshakeResponse] would build for the same [capabilities], and
/// nothing past that -- see [_writeHandshakeHeader].
///
/// This is sent before the TLS handshake, so the server knows to expect
/// it; the user name and everything after it stays out because it has to
/// travel encrypted, in the full response sent again once the socket is
/// upgraded. [capabilities] must be the same value passed to that later
/// call to [buildHandshakeResponse] -- a mismatch would leave the server
/// reading the encrypted response under the wrong idea of its layout.
Uint8List buildSslRequest(int capabilities) {
  final writer = ByteWriter();
  _writeHandshakeHeader(writer, capabilities);
  return writer.toBytes();
}
