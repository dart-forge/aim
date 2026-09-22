import 'dart:typed_data';

import 'package:aim_mysql/src/exceptions.dart';
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
