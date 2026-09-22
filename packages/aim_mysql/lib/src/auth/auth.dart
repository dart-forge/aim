import 'dart:convert';
import 'dart:typed_data';

import 'package:aim_mysql/src/auth/caching_sha2.dart';
import 'package:aim_mysql/src/auth/native_password.dart';
import 'package:aim_mysql/src/auth/rsa_oaep.dart';
import 'package:aim_mysql/src/exceptions.dart';
import 'package:aim_mysql/src/protocol/handshake.dart';
import 'package:aim_mysql/src/protocol/packets.dart';
import 'package:aim_mysql/src/protocol/wire.dart';

/// How many packets [authenticate] will receive from the server before
/// giving up.
///
/// Every real exchange finishes in one round trip (a fast path, or a
/// plugin with no second round) to three (an auth switch followed by a
/// full caching_sha2_password authentication over a connection without
/// TLS). Ten is not a tuned estimate of the longest real exchange -- it
/// only needs to be bigger than that, so that a server stuck alternating
/// auth-switch requests forever fails fast instead of hanging the caller.
/// This protocol has no packet a client can send to resynchronise once
/// confused, so the alternative to a cap here is an exchange that never
/// ends.
const int _maxRoundTrips = 10;

/// The narrow surface [authenticate] drives the authentication exchange
/// through.
///
/// Deliberately without a socket, a buffer, or anything about how bytes
/// actually move: send one packet's payload, receive one packet's
/// payload, and know whether the channel underneath is already encrypted.
/// A fake that implements just this can script every path through
/// [authenticate], including ones a real server only takes under
/// configurations -- no TLS, a public-key round trip -- that are
/// inconvenient to set up for every test run.
abstract interface class AuthTransport {
  /// Sends [payload] as the next packet.
  Future<void> send(Uint8List payload);

  /// Waits for and returns the next packet's payload.
  Future<Uint8List> receive();

  /// Whether this channel already speaks TLS.
  ///
  /// Fixed for as long as authentication runs: promoting a plaintext
  /// socket to TLS happens before [authenticate] is ever called, so this
  /// value never changes out from under it.
  bool get isSecure;
}

/// Thrown when the server names an authentication plugin this driver does
/// not implement -- in the initial handshake, or later in an auth switch
/// request.
///
/// Carries [pluginName] because "unsupported plugin" alone gives whoever
/// reads it nothing to act on; the name is what they need, either to
/// configure the account differently or to know which plugin to ask for
/// support for.
final class UnsupportedAuthPlugin implements Exception {
  UnsupportedAuthPlugin(this.pluginName);

  /// The plugin name the server asked for, e.g. `sha256_password`.
  final String pluginName;

  @override
  String toString() =>
      'UnsupportedAuthPlugin: the server asked for authentication plugin '
      '"$pluginName", which this driver does not implement';
}

/// Drives one authentication exchange over [transport]: builds the first
/// response from [initialPluginName] and [initialScramble] and sends it
/// wrapped in a handshake response, then follows wherever the server takes
/// the exchange -- an auth switch to a different plugin and scramble, a
/// plugin-specific round of `AuthMoreData`, or the final OK or ERR -- until
/// it is over.
///
/// [capabilities] is the client capability flags already negotiated
/// against the server's own; [user], [password] and [database] are the
/// credentials to authenticate with (a `null` [database] is normal --
/// [capabilities] alone decides whether the handshake response carries
/// one). Any TLS upgrade has already happened on [transport] by the time
/// this is called: [AuthTransport.isSecure] only reports that fact, and
/// authenticate never tries to change it.
///
/// Only two plugins are understood: `mysql_native_password` and
/// `caching_sha2_password`. Any other name -- as [initialPluginName], or
/// later from an auth switch request -- fails with [UnsupportedAuthPlugin]
/// before anything more is sent. A server can default to
/// `mysql_native_password` for a given account and still open every
/// connection to it by naming `caching_sha2_password` in its initial
/// handshake, with the switch back to the account's real plugin happening
/// through an auth-switch-request rather than in the handshake itself --
/// so the switch branch below is not a fallback for a rare case; for that
/// configuration, it is the only path that ever authenticates anything.
///
/// Only the first packet -- the one built from [initialPluginName] and
/// [initialScramble] -- is wrapped in a handshake response. Every packet
/// after it, including the one an auth switch triggers, is the bare auth
/// token: wrapping a second one would leave the server reading its own
/// 32-byte capability-flags prefix as the token itself.
///
/// Returns normally on OK. Throws the exception [mysqlErrorFor] builds for
/// an ERR, at any point in the exchange, not only as the first reply.
/// Throws [MySqlProtocolException] if a plugin sends `AuthMoreData` it has
/// no defined use for (`mysql_native_password` never sends any), if
/// `caching_sha2_password` sends a marker byte other than `0x03` or
/// `0x04`, or if the exchange has not finished after [_maxRoundTrips]
/// packets.
Future<void> authenticate({
  required AuthTransport transport,
  required int capabilities,
  required String user,
  required String password,
  String? database,
  required String initialPluginName,
  required Uint8List initialScramble,
}) async {
  var pluginName = initialPluginName;
  var scramble = initialScramble;

  await transport.send(
    buildHandshakeResponse(
      capabilities: capabilities,
      user: user,
      authResponse: _authResponseToken(
        pluginName: pluginName,
        password: password,
        scramble: scramble,
      ),
      authPluginName: pluginName,
      database: database,
    ),
  );

  for (var round = 0; round < _maxRoundTrips; round++) {
    final packet = parseAuthPhasePacket(await transport.receive());

    switch (packet) {
      case OkPacket():
        return;

      case ErrPacket errPacket:
        throw mysqlErrorFor(errPacket);

      case AuthSwitchRequest switchRequest:
        // A fresh scramble arrives with the switch. Hashing against the
        // handshake's own scramble instead would produce a token of
        // exactly the right length that the server still refuses, with
        // nothing about its shape to explain why.
        pluginName = switchRequest.pluginName;
        scramble = switchRequest.scramble;
        await transport.send(
          _authResponseToken(
            pluginName: pluginName,
            password: password,
            scramble: scramble,
          ),
        );

      case AuthMoreData(data: final data):
        await _handleAuthMoreData(
          data: data,
          pluginName: pluginName,
          password: password,
          scramble: scramble,
          transport: transport,
        );

      case EofPacket():
      case ResultSetHeader():
        // parseAuthPhasePacket never produces either of these during
        // authentication; named here so this switch stays exhaustive over
        // every ServerPacket subtype instead of trusting that promise
        // silently.
        throw MySqlProtocolException(
          'received a ${packet.runtimeType} during authentication, which '
          'is not a packet this phase of the protocol ever sends',
        );
    }
  }

  throw MySqlProtocolException(
    'authentication did not finish within $_maxRoundTrips round trip(s); '
    'the server kept the exchange going instead of ever sending OK or ERR',
  );
}

/// The auth-response token for [pluginName], given [password] and
/// [scramble] -- shared by the initial handshake response and by an auth
/// switch, since both are "build the token this plugin expects" with
/// nothing else different about them.
///
/// Throws [UnsupportedAuthPlugin] for any plugin other than
/// `mysql_native_password` or `caching_sha2_password`, before the caller
/// has sent anything for this round.
Uint8List _authResponseToken({
  required String pluginName,
  required String password,
  required Uint8List scramble,
}) {
  switch (pluginName) {
    case 'mysql_native_password':
      return nativePasswordToken(password: password, scramble: scramble);
    case 'caching_sha2_password':
      return cachingSha2FastAuthToken(password: password, scramble: scramble);
    default:
      throw UnsupportedAuthPlugin(pluginName);
  }
}

/// Handles one `AuthMoreData` packet arriving while [pluginName] is the
/// plugin currently running, sending whatever response it calls for over
/// [transport] -- or nothing, when none is called for.
///
/// `mysql_native_password` has no second round, so any [pluginName] other
/// than `caching_sha2_password` reaching here is already a protocol
/// failure: the only plugin this driver supports that can send this
/// packet at all is the other one.
///
/// For `caching_sha2_password`, [data]'s first byte decides what happens:
///
/// | first byte | meaning | response |
/// |---|---|---|
/// | `0x03` | the server's hash cache already has this password | nothing -- the next packet is the OK |
/// | `0x04` | full authentication is required | see below |
///
/// The fast path (`0x03`) exists precisely so a connection does not need
/// TLS on every authentication: it is the server's cache that makes the
/// second round unnecessary, not the transport's encryption. TLS only
/// matters once full authentication (`0x04`) is actually reached, and even
/// then only to decide how the password travels: in the clear, inside a
/// TLS session that is already doing the job encryption would otherwise
/// do, when [AuthTransport.isSecure] is true; RSA-encrypted with the
/// server's public key, requested with a single `0x02` byte, when it is
/// not. Requesting the key when TLS is already protecting the connection
/// would just be a wasted round trip.
///
/// Throws [MySqlProtocolException] for any other first byte, or for an
/// empty packet, since neither is defined for this plugin.
Future<void> _handleAuthMoreData({
  required Uint8List data,
  required String pluginName,
  required String password,
  required Uint8List scramble,
  required AuthTransport transport,
}) async {
  if (pluginName != 'caching_sha2_password') {
    throw MySqlProtocolException(
      '$pluginName sent AuthMoreData, which this driver has never seen it '
      'do',
    );
  }
  if (data.isEmpty) {
    throw MySqlProtocolException(
      'caching_sha2_password sent an empty AuthMoreData packet',
    );
  }

  switch (data[0]) {
    case 0x03:
      return;

    case 0x04:
      final passwordWithNul = Uint8List.fromList([...utf8.encode(password), 0]);
      if (transport.isSecure) {
        await transport.send(passwordWithNul);
        return;
      }
      await transport.send(Uint8List.fromList([0x02]));
      final pem = decodeUtf8(await _expectPublicKey(transport));
      final key = parsePublicKeyPem(pem);
      final masked = xorWithScramble(passwordWithNul, scramble);
      await transport.send(rsaOaepEncrypt(message: masked, key: key));
      return;

    default:
      throw MySqlProtocolException(
        'caching_sha2_password sent an AuthMoreData packet with an '
        'unrecognised marker byte '
        '0x${data[0].toRadixString(16).padLeft(2, "0")}',
      );
  }
}

/// Reads the packet that answers a `0x02` request for the server's RSA
/// public key, and returns its raw bytes -- the PEM text, undecoded.
///
/// Throws whatever [mysqlErrorFor] builds if the server answers with an
/// ERR instead: authentication can still fail at this point -- an account
/// that no longer exists, say -- and that has to surface the same way it
/// does everywhere else in this exchange, not disappear into a generic
/// protocol error. Throws [MySqlProtocolException] for anything else:
/// nothing but the key or an ERR is defined here.
Future<Uint8List> _expectPublicKey(AuthTransport transport) async {
  final packet = parseAuthPhasePacket(await transport.receive());
  switch (packet) {
    case AuthMoreData(data: final data):
      return data;

    case ErrPacket errPacket:
      throw mysqlErrorFor(errPacket);

    case OkPacket():
    case AuthSwitchRequest():
    case EofPacket():
    case ResultSetHeader():
      throw MySqlProtocolException(
        "expected the server's RSA public key but received a "
        '${packet.runtimeType} instead',
      );
  }
}
