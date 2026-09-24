import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aim_database/aim_database.dart';
import 'package:aim_mysql/src/auth/auth.dart';
import 'package:aim_mysql/src/exceptions.dart';
import 'package:aim_mysql/src/protocol/handshake.dart';
import 'package:aim_mysql/src/protocol/packet.dart';
import 'package:aim_mysql/src/protocol/packets.dart';
import 'package:aim_mysql/src/statement.dart';

/// How this driver decides whether, and how strictly, to use TLS.
///
/// Modelled on libpq's `sslmode`, minus `allow`: that mode tries plaintext
/// first and upgrades only if the server insists, which is the opposite
/// priority of [prefer]. Nothing in this driver's target servers needs that
/// order, so it is left out rather than implemented as a name nobody
/// exercises.
enum MySqlSslMode {
  /// Never use TLS, whatever the server offers.
  disable,

  /// Use TLS when the server offers it, plaintext otherwise. Never verifies
  /// the certificate: the point is resistance to passive eavesdropping on a
  /// network this driver does not otherwise control, not authenticating the
  /// server.
  prefer,

  /// Always use TLS; refuse to connect if the server does not offer it.
  /// Does not verify the certificate -- see [prefer].
  require,

  /// [require], plus verify the certificate against a trusted CA.
  ///
  /// Behaves exactly like [verifyFull]: `dart:io`'s [SecureSocket] has no
  /// way to check a certificate's CA without also checking that it names
  /// the host being connected to, so there is no weaker verification to
  /// offer under this name.
  verifyCa,

  /// [require], plus verify the certificate against a trusted CA and
  /// confirm it names the host being connected to.
  verifyFull,
}

/// Everything [MySqlConnection.connect] needs: where the server is, who to
/// authenticate as, and how to treat TLS.
final class MySqlConnectionSettings {
  MySqlConnectionSettings({
    required this.host,
    this.port = 3306,
    required this.user,
    this.password = '',
    this.database,
    this.sslMode = MySqlSslMode.prefer,
    this.caFile,
    this.connectTimeout = const Duration(seconds: 10),
    this.queryTimeout = const Duration(seconds: 30),
    this.allowPublicKeyRetrieval = false,
  });

  /// Parses a `mysql://user:password@host:port/database?sslmode=...`
  /// connection string.
  ///
  /// `port` defaults to `3306`. `password` defaults to the empty string --
  /// a real shape for a MySQL account, distinct from no password field at
  /// all only in that the latter cannot arise here (`userInfo` either has
  /// no `:`, giving an empty password, or does). `database` is `null` when
  /// the path is empty or just `/`, which is different from a database
  /// whose name is the empty string: the server would refuse that outright,
  /// while `null` means no database is selected at all.
  ///
  /// [Uri.parse] does not decode `userInfo` on its own, so the user and
  /// password are split apart -- on the first unencoded `:` -- before each
  /// half is run through [Uri.decodeComponent]. Splitting first matters: a
  /// password containing a literal `:` has to arrive percent-encoded to
  /// survive the URL, so it never introduces a second unencoded `:` for
  /// this to trip over.
  ///
  /// `sslmode` defaults to [MySqlSslMode.prefer], never [MySqlSslMode.disable]
  /// -- leaving it out of the URL must not quietly produce a plaintext
  /// connection to a network database. Throws [ArgumentError] for a scheme
  /// other than `mysql`, a missing host, a missing user (MySQL has no
  /// equivalent of falling back to the OS user), or an `sslmode` this driver
  /// does not implement.
  factory MySqlConnectionSettings.parse(String url) {
    final uri = Uri.parse(url);

    if (uri.scheme != 'mysql') {
      throw ArgumentError.value(
        url,
        'url',
        'scheme must be "mysql", not "${uri.scheme}"',
      );
    }
    if (uri.host.isEmpty) {
      throw ArgumentError.value(url, 'url', 'no host');
    }
    if (uri.userInfo.isEmpty) {
      throw ArgumentError.value(
        url,
        'url',
        'no user; MySQL has no equivalent of falling back to the OS user',
      );
    }

    final colonAt = uri.userInfo.indexOf(':');
    final user = Uri.decodeComponent(
      colonAt == -1 ? uri.userInfo : uri.userInfo.substring(0, colonAt),
    );
    final password = colonAt == -1
        ? ''
        : Uri.decodeComponent(uri.userInfo.substring(colonAt + 1));

    final path = uri.path;
    final database = (path.isEmpty || path == '/') ? null : path.substring(1);

    final sslModeParam = uri.queryParameters['sslmode'];

    return MySqlConnectionSettings(
      host: uri.host,
      port: uri.hasPort ? uri.port : 3306,
      user: user,
      password: password,
      database: database,
      sslMode: sslModeParam == null
          ? MySqlSslMode.prefer
          : _parseSslMode(sslModeParam),
      caFile: uri.queryParameters['sslrootcert'],
      allowPublicKeyRetrieval:
          uri.queryParameters['allowPublicKeyRetrieval'] == 'true',
      queryTimeout: _parseQueryTimeout(uri.queryParameters['queryTimeout']),
    );
  }

  final String host;
  final int port;
  final String user;
  final String password;
  final String? database;
  final MySqlSslMode sslMode;

  /// A CA certificate file to trust in addition to (`verify-ca`) or instead
  /// of the system roots, for [MySqlSslMode.verifyCa] and
  /// [MySqlSslMode.verifyFull]. Ignored by every other mode.
  final String? caFile;

  /// Bounds only the initial `Socket.connect`, not the handshake,
  /// authentication or session setup that follow it.
  final Duration connectTimeout;

  /// Bounds the handshake and authentication that follow `Socket.connect`,
  /// and every reply this connection waits for afterwards -- one bound per
  /// round trip, not a total budget for the connection's whole life. A
  /// server that stops answering (a network partition, a lock held
  /// forever on the other end) would otherwise hang the caller, and
  /// [close] and pool shutdown, indefinitely: nothing else in this driver
  /// times out a wait for a reply.
  ///
  /// On expiry the socket is closed and the connection is marked unusable,
  /// so a pool discards it instead of handing it to the next caller.
  final Duration queryTimeout;

  /// Whether this driver may fetch the server's RSA public key over an
  /// unencrypted connection, when `caching_sha2_password` falls back to
  /// full authentication and TLS is not in use.
  ///
  /// Defaults to `false`: doing this by default would let anyone on the
  /// network path between this driver and the server read the key
  /// exchange and, with it, recover the password. Set `true` (or
  /// `allowPublicKeyRetrieval=true` on the connection URL) only when that
  /// risk is accepted -- typically because the network itself is already
  /// trusted -- or use `sslmode` to encrypt the connection instead.
  final bool allowPublicKeyRetrieval;
}

/// Parses the `queryTimeout` URL query parameter -- a whole number of
/// seconds -- or falls back to [MySqlConnectionSettings.queryTimeout]'s own
/// default when [raw] is `null`. Throws [ArgumentError] for anything else
/// that is not a valid non-negative integer.
Duration _parseQueryTimeout(String? raw) {
  if (raw == null) return const Duration(seconds: 30);
  final seconds = int.tryParse(raw);
  if (seconds == null || seconds < 0) {
    throw ArgumentError.value(
      raw,
      'queryTimeout',
      'must be a non-negative whole number of seconds',
    );
  }
  return Duration(seconds: seconds);
}

MySqlSslMode _parseSslMode(String raw) => switch (raw.toLowerCase()) {
  'disable' => MySqlSslMode.disable,
  'prefer' => MySqlSslMode.prefer,
  'require' => MySqlSslMode.require,
  'verify-ca' => MySqlSslMode.verifyCa,
  'verify-full' => MySqlSslMode.verifyFull,
  _ => throw ArgumentError.value(
    raw,
    'sslmode',
    'not a mode this driver implements: "$raw"',
  ),
};

/// The command bytes this connection sends. Each is the first byte of the
/// packet it names.
const int _comQuit = 0x01;
const int _comQuery = 0x03;
const int _comPing = 0x0e;

/// One packet's payload, handed back by [MySqlConnection.exchange] for
/// [MySqlConnection] to read as many times as the command's reply needs.
abstract interface class ResponseReader {
  /// Waits for and returns the next packet's payload.
  Future<Uint8List> next();
}

/// An open connection to one MySQL server: the socket (upgraded to TLS when
/// asked), the completed authentication, and the pinned session.
///
/// Every round trip after [connect] goes through [exchange], which
/// serializes them -- this protocol has no packet a client can send to
/// resynchronise once two round trips interleave, so nothing here risks
/// that happening. A round trip that fails on anything other than a
/// server-reported [MySqlException] is treated as having left the stream
/// in an unknown state: [isOpen] becomes `false` and the connection is
/// never used again. Recovery is not attempted, because there is nothing
/// short of a fresh connection to recover to.
final class MySqlConnection {
  MySqlConnection._(this._channel, this._queryTimeout) {
    _statements = statementCacheFor(this);
  }

  final _PacketChannel _channel;
  final Duration _queryTimeout;
  bool _isOpen = true;
  late String _sqlMode;
  late final StatementCache _statements;

  /// This connection's cache of prepared statements: created alongside the
  /// connection itself, and emptied -- closing every statement it holds --
  /// by [close].
  ///
  /// Per connection rather than shared across a pool, because the
  /// statement ids inside it are: a cache shared across several
  /// connections would hand one connection's id to another, which would
  /// either execute a different statement than the one asked for or fail
  /// outright.
  StatementCache get statements => _statements;

  /// Chains every [exchange] and [close] so that at most one is ever
  /// touching the socket at a time. Held for as long as the caller's
  /// `readResponse` is running, not just for the send -- see [exchange].
  Future<void> _lock = Future<void>.value();

  /// `true` until [close] has run, or until a round trip has failed in a
  /// way that leaves the byte stream's position unknown.
  bool get isOpen => _isOpen;

  /// The session's `sql_mode`, as of the last time it was read: at
  /// [connect] time, or since then, whenever [refreshSqlMode] was called.
  ///
  /// This driver never writes `sql_mode` -- an application's own choice of
  /// it is none of this driver's business to override -- but it reads it,
  /// because [dialect] depends on it: `NO_BACKSLASH_ESCAPES` changes where a
  /// string literal ends, which the placeholder scanner has to know.
  String get sqlMode => _sqlMode;

  /// The lexical rules [sqlMode] implies, for scanning a statement's
  /// placeholders. Nothing but whether `NO_BACKSLASH_ESCAPES` is set
  /// differs between the two dialects this driver ever returns here.
  SqlDialect get dialect => _sqlMode.contains('NO_BACKSLASH_ESCAPES')
      ? SqlDialect.mysqlWithoutBackslashEscapes
      : SqlDialect.mysql;

  /// Connects to the server [settings] describes: opens the socket,
  /// upgrades it to TLS when [MySqlConnectionSettings.sslMode] calls for
  /// it, authenticates, and pins the session's time zone before returning.
  ///
  /// The capabilities this driver asks for are decided once, from the
  /// initial handshake and [settings], before any TLS upgrade -- MySQL
  /// requires the same capability flags to be sent both in the pre-upgrade
  /// `SSLRequest` and in the real handshake response that follows it, so
  /// they cannot be decided from anything the (still plaintext) server has
  /// said about which authentication plugin it wants.
  ///
  /// [MySqlSslMode.prefer] uses TLS only if the server's handshake offers
  /// it, falling back to plaintext otherwise. [MySqlSslMode.require],
  /// [MySqlSslMode.verifyCa] and [MySqlSslMode.verifyFull] all demand TLS
  /// unconditionally; [negotiateCapabilities] is what throws
  /// [MySqlProtocolException] if the server does not offer it in that case.
  ///
  /// Throws whatever the failing step throws -- most commonly
  /// [MySqlProtocolException] for a handshake this driver cannot make sense
  /// of, a [SecureSocket] exception for a TLS upgrade or certificate
  /// [MySqlSslMode.verifyFull] refuses, or a [MySqlException] subtype for
  /// authentication the server refuses. The socket is always closed before
  /// any of these propagate; nothing is left open on a failed connect.
  static Future<MySqlConnection> connect(
    MySqlConnectionSettings settings,
  ) async {
    final socket = await Socket.connect(
      settings.host,
      settings.port,
      timeout: settings.connectTimeout,
    );

    var channel = _PacketChannel(socket);
    try {
      return await _handshakeAndAuthenticate(
        channel: channel,
        socket: socket,
        settings: settings,
        setChannel: (newChannel) => channel = newChannel,
      ).timeout(
        settings.queryTimeout,
        onTimeout: () => throw TimeoutException(
          'connecting to the server (handshake and authentication) did '
          'not finish within ${settings.queryTimeout}',
        ),
      );
    } catch (_) {
      try {
        await channel.destroy();
      } catch (_) {
        // Best-effort cleanup on the way out; the original failure is what
        // the caller needs to see, not a secondary problem closing an
        // already-broken socket.
      }
      rethrow;
    }
  }

  /// The handshake-and-authenticate half of [connect], pulled out on its
  /// own so [connect] can wrap it in a single [Duration.timeout] bounding
  /// the whole exchange -- there is no reply to a stuck server yet, so
  /// [exchange]'s own per-call timeout is not in play until [MySqlConnection]
  /// exists at the very end of this.
  ///
  /// [setChannel] writes a TLS upgrade's new channel back into [connect]'s
  /// own local variable, so that method's `catch` block destroys whichever
  /// channel is actually live -- the plaintext one, or the secure one that
  /// replaced it -- rather than always the one it started with.
  static Future<MySqlConnection> _handshakeAndAuthenticate({
    required _PacketChannel channel,
    required Socket socket,
    required MySqlConnectionSettings settings,
    required void Function(_PacketChannel) setChannel,
  }) async {
    final firstPacket = await channel.readPacket();
    if (isServerRefusalBeforeHandshake(firstPacket)) {
      // The server is refusing the connection outright -- too many
      // connections, a blocked host, an unprivileged one -- rather than
      // starting a handshake at all. Reporting it as a server error
      // rather than a bad protocol version is what lets a caller
      // catching MySqlException read the real errno and message.
      throw mysqlErrorFor(parseCommandPacket(firstPacket) as ErrPacket);
    }
    final handshake = parseInitialHandshake(firstPacket);
    final pluginName = handshake.authPluginName;
    if (pluginName == null) {
      throw MySqlProtocolException(
        'the initial handshake did not name an authentication plugin, '
        'which this driver has no way to authenticate without',
      );
    }

    final serverOffersTls = handshake.capabilities & Capabilities.ssl != 0;
    final useTls = switch (settings.sslMode) {
      MySqlSslMode.disable => false,
      MySqlSslMode.prefer => serverOffersTls,
      MySqlSslMode.require ||
      MySqlSslMode.verifyCa ||
      MySqlSslMode.verifyFull => true,
    };

    final capabilities = negotiateCapabilities(
      handshake,
      useTls: useTls,
      withDatabase: settings.database != null,
    );

    var isSecure = false;
    int nextSequenceId;
    if (useTls) {
      final sslRequestId = channel.lastSequenceId + 1;
      channel.write(framePacket(buildSslRequest(capabilities), sslRequestId));
      await channel.flush();

      // The socket hands itself over to SecureSocket.secure below; nothing
      // may read from the plaintext side of it again after this.
      channel.pauseForUpgrade();
      final secureSocket = await SecureSocket.secure(
        socket,
        host: settings.host,
        context: _securityContextFor(settings.caFile),
        onBadCertificate: _verifiesCertificate(settings.sslMode)
            ? null
            : (_) => true,
      );

      channel = _PacketChannel(secureSocket);
      setChannel(channel);
      isSecure = true;
      nextSequenceId = (sslRequestId + 1) & 0xff;
    } else {
      nextSequenceId = (channel.lastSequenceId + 1) & 0xff;
    }

    await authenticate(
      transport: _ConnectionAuthTransport(
        channel,
        isSecure: isSecure,
        nextSequenceId: nextSequenceId,
      ),
      capabilities: capabilities,
      user: settings.user,
      password: settings.password,
      database: settings.database,
      initialPluginName: pluginName,
      initialScramble: handshake.authPluginData,
      allowPublicKeyRetrieval: settings.allowPublicKeyRetrieval,
    );

    final connection = MySqlConnection._(channel, settings.queryTimeout);
    await connection._pinSession();
    return connection;
  }

  /// Runs one command: sends [command] followed by [body] as a single
  /// packet (split into several if [body] is large), then hands [readResponse]
  /// a [ResponseReader] to pull the reply from, one packet at a time, for
  /// as long as the command's reply shape needs.
  ///
  /// Serialized against every other [exchange] and [close] on this
  /// connection: the lock is not released until [readResponse] itself has
  /// finished, not merely once the command has been sent. Exposing send and
  /// receive as separate public steps and trusting callers to keep them in
  /// order was rejected for this reason -- this protocol has no
  /// resynchronisation point, so the moment two round trips interleave, the
  /// connection is desynchronised for good with no way back. Holding the
  /// lock for the whole call is what makes that impossible instead of
  /// merely discouraged.
  ///
  /// The sequence id for [command]'s packet is always `0`: MySQL restarts
  /// the numbering at the start of every command, independently of
  /// whatever it reached during the connection and authentication that
  /// preceded it.
  ///
  /// Throws [StateError] with [mysqlClosedMessage] if the connection is
  /// already closed, without touching the socket. Any other failure
  /// out of [readResponse] -- other than a [MySqlException], the server
  /// cleanly refusing the command -- is treated as having left the byte
  /// stream at an unknown position: [isOpen] becomes `false` and the
  /// socket is torn down before the error is rethrown.
  Future<T> exchange<T>(
    int command,
    Uint8List body,
    Future<T> Function(ResponseReader) readResponse,
  ) async {
    if (!_isOpen) {
      throw StateError(mysqlClosedMessage);
    }

    return _withLock(() async {
      if (!_isOpen) {
        throw StateError(mysqlClosedMessage);
      }
      try {
        final payload = Uint8List.fromList([command, ...body]);
        for (final packet in framePackets(payload, 0)) {
          _channel.write(packet);
        }
        await _channel.flush();
        return await readResponse(_ExchangeResponseReader(_channel)).timeout(
          _queryTimeout,
          onTimeout: () => throw TimeoutException(
            "waiting for the server's reply took longer than "
            '$_queryTimeout',
          ),
        );
      } on MySqlException {
        // The server refused the command cleanly; its reply packet fully
        // arrived and ended the exchange the same way a successful one
        // would. The connection is still exactly as usable as before.
        rethrow;
      } catch (_) {
        await _forceClose();
        rethrow;
      }
    });
  }

  /// A cheap liveness probe: sends `COM_PING` and expects `OK` back.
  ///
  /// Only ever resolves `true` or throws -- there is no reply to a ping
  /// other than `OK` or an `ERR` this driver surfaces as a [MySqlException]
  /// -- but stays `Future<bool>` rather than `Future<void>` because that is
  /// the shape a connection pool's own health check wants to call without
  /// wrapping every ping in a try/catch itself.
  Future<bool> ping() => exchange<bool>(_comPing, Uint8List(0), (reader) async {
    final packet = parseCommandPacket(await reader.next());
    switch (packet) {
      case OkPacket():
        return true;
      case ErrPacket err:
        throw mysqlErrorFor(err);
      case ResultSetHeader():
      case EofPacket():
      case AuthSwitchRequest():
      case AuthMoreData():
        throw MySqlProtocolException(
          'expected OK or ERR in reply to a ping, got a ${packet.runtimeType}',
        );
    }
  });

  /// Empties [statements] -- closing every statement it holds on the
  /// server -- then sends `COM_QUIT` and closes the socket, without
  /// waiting for a reply to either: neither has one, and waiting would
  /// add a timeout to every close. Safe to call more than once; every
  /// call after the first does nothing.
  Future<void> close() async {
    if (!_isOpen) return;
    await statements.clear();
    await _withLock(() async {
      if (!_isOpen) return;
      _isOpen = false;
      try {
        _channel.write(framePacket(Uint8List.fromList([_comQuit]), 0));
        await _channel.flush();
      } catch (_) {
        // A write failing here just means the socket was already unusable;
        // destroying it below is what close is for either way.
      }
      await _channel.destroy();
    });
  }

  /// Re-reads `sql_mode` from the session, for a caller that just changed
  /// it with `SET SESSION sql_mode = ...`.
  ///
  /// [sqlMode] and [dialect] are cached from [connect] time onward, since
  /// reading them off the session on every statement would add a round
  /// trip nothing else needs. That cache is only right until something
  /// changes the session's `sql_mode` out from under it -- after which
  /// [dialect] would misjudge where a string literal ends, and a
  /// placeholder inside one would be scanned as though it were not. This is
  /// the escape hatch: called only when the SQL about to run is itself a
  /// `SET ... SQL_MODE ...`, not on every statement.
  Future<void> refreshSqlMode() async {
    _sqlMode = await _fetchSqlMode();
  }

  /// Pins the session's time zone and reads its `sql_mode`, once, right
  /// after authentication succeeds.
  ///
  /// Only the time zone is ever written. The character set needs no
  /// separate round trip at all: the single byte this driver already sends
  /// in the handshake response decides `character_set_client`,
  /// `_connection` and `_results` together, so `SET NAMES` would only spend
  /// a round trip restating what the server was already told. `sql_mode` is
  /// read, never written -- see [refreshSqlMode].
  Future<void> _pinSession() async {
    const pinTimeZoneSql = "SET time_zone = '+00:00'";
    await exchange<void>(_comQuery, utf8.encode(pinTimeZoneSql), (
      reader,
    ) async {
      final packet = parseCommandPacket(await reader.next());
      switch (packet) {
        case OkPacket():
          return;
        case ErrPacket err:
          throw mysqlErrorFor(err, sql: pinTimeZoneSql);
        case ResultSetHeader():
        case EofPacket():
        case AuthSwitchRequest():
        case AuthMoreData():
          throw MySqlProtocolException(
            'expected OK while pinning the session time zone, got a '
            '${packet.runtimeType}',
          );
      }
    });
    _sqlMode = await _fetchSqlMode();
  }

  /// Runs `SELECT @@session.sql_mode` and reads back its value through
  /// [fetchSingleValue], failing loudly if the server ever answers with SQL
  /// NULL -- which it never does for a real session, but `fetchSingleValue`
  /// itself has to allow for a null result (e.g. a bare `SET`), so this is
  /// the one place that turns "no value" into a protocol error rather than
  /// a shrug.
  Future<String> _fetchSqlMode() async {
    final sqlMode = await fetchSingleValue('SELECT @@session.sql_mode');
    if (sqlMode == null) {
      throw MySqlProtocolException(
        '@@session.sql_mode came back as SQL NULL, which a real server '
        'never sends',
      );
    }
    return sqlMode;
  }

  /// Runs [sql] as a `COM_QUERY`: the text protocol, for a statement that
  /// cannot be prepared at all -- `CREATE PROCEDURE`, `START TRANSACTION`,
  /// `SET SESSION`, and the like. [statements] and `executeStatement` are
  /// how every other statement runs, always as a prepared one -- but a
  /// caller's own parameterless `SET` is routed through this method too
  /// (see `_runQueryable` in `mysql_database.dart`), since `SET` cannot be
  /// prepared either.
  ///
  /// Reads every result set the reply carries -- see [MySqlResultSets],
  /// looping for as long as the status flags say another one follows --
  /// decoding each row as [String] or `null`, never as a typed Dart value:
  /// there is no per-column type to decode against for a statement this
  /// driver never binds parameters to or reads application data from.
  Future<MySqlResultSets> runTextQuery(String sql) {
    return exchange<MySqlResultSets>(
      _comQuery,
      utf8.encode(sql),
      (reader) => readTextResultSets(reader, sql: sql),
    );
  }

  /// Runs [sql] through [runTextQuery] and returns one value out of its
  /// reply: the last column of its one row, or `null` if [sql] produced no
  /// result set at all (a plain `OK`, as `SET` statements do).
  ///
  /// The *last* column, not the only one: this is what lets the same
  /// method read both a single-column `SELECT` and a two-column
  /// `SHOW STATUS LIKE '...'` (`Variable_name`, `Value`) without the caller
  /// having to know which shape it is asking for -- the value the caller
  /// actually wants is always the rightmost one either way.
  ///
  /// Made public, rather than kept as a private helper, because a caller
  /// outside this class -- this driver's own tests, most immediately --
  /// has no other way to read the server's own accounting of something
  /// (e.g. `Ssl_cipher`) instead of trusting this driver's claim about
  /// itself.
  Future<String?> fetchSingleValue(String sql) async {
    final withRows = (await runTextQuery(sql)).withRows;
    if (withRows == null) {
      // No result set at all -- e.g. a SET statement -- so there is no
      // value to report.
      return null;
    }
    return withRows.rows.single.last as String?;
  }

  /// Marks the connection unusable and tears down the socket, without
  /// attempting to send anything more: whatever [exchange] was doing when
  /// it caught the error that led here may have left the byte stream at a
  /// position nothing can safely write to.
  Future<void> _forceClose() async {
    if (!_isOpen) return;
    _isOpen = false;
    await _channel.destroy();
  }

  /// Runs [body] after every previously queued [exchange] or [close] on
  /// this connection has finished, and not before.
  Future<T> _withLock<T>(Future<T> Function() body) async {
    final previous = _lock;
    final done = Completer<void>();
    _lock = done.future;
    await previous;
    try {
      return await body();
    } finally {
      done.complete();
    }
  }
}

/// Whether [mode] rejects a certificate `SecureSocket` cannot verify,
/// rather than accepting the connection anyway.
///
/// [MySqlSslMode.verifyCa] and [MySqlSslMode.verifyFull] answer the same
/// way here on purpose -- see [MySqlSslMode.verifyCa]'s doc comment.
bool _verifiesCertificate(MySqlSslMode mode) => switch (mode) {
  MySqlSslMode.verifyCa || MySqlSslMode.verifyFull => true,
  MySqlSslMode.disable || MySqlSslMode.prefer || MySqlSslMode.require => false,
};

/// The trusted-certificate set a TLS upgrade should use: just [caFile] when
/// one was given, or `null` for `SecureSocket.secure` to fall back to its
/// own default (the system's trusted roots).
SecurityContext? _securityContextFor(String? caFile) {
  if (caFile == null) return null;
  return SecurityContext(withTrustedRoots: false)
    ..setTrustedCertificates(caFile);
}

/// Bridges a socket's raw byte stream to whole MySQL packets, tracking the
/// sequence id of the last one [readPacket] returned.
///
/// At most one [readPacket] call is ever outstanding on a given instance.
/// [MySqlConnection] serializes every round trip through it, and the
/// handshake and authentication this is also used for is itself a strict,
/// alternating exchange -- so a single pending completer is enough; this is
/// not a general-purpose multiplexer over the socket.
final class _PacketChannel {
  _PacketChannel(this._socket) {
    _subscription = _socket.listen(
      _onData,
      onError: _onError,
      onDone: () => _onError(
        MySqlProtocolException('the socket closed while a packet was expected'),
      ),
    );
  }

  final Socket _socket;
  late final StreamSubscription<Uint8List> _subscription;
  final PacketReassembler _reassembler = PacketReassembler();
  Completer<Uint8List>? _waiting;
  Object? _deadWith;
  StackTrace? _deadTrace;

  /// The sequence id of the last packet [readPacket] has handed back, or
  /// `0` if it never has yet -- which is also the initial handshake's own
  /// sequence id, so a caller that has just read that packet and nothing
  /// else already sees the right value without a special case for it.
  int get lastSequenceId => _reassembler.lastSequenceId;

  void _onData(Uint8List chunk) {
    _reassembler.add(chunk);
    final waiting = _waiting;
    if (waiting == null) return;
    final payload = _reassembler.take();
    if (payload != null) {
      _waiting = null;
      waiting.complete(payload);
    }
  }

  void _onError(Object error, [StackTrace? stackTrace]) {
    _deadWith = error;
    _deadTrace = stackTrace;
    final waiting = _waiting;
    if (waiting != null) {
      _waiting = null;
      waiting.completeError(error, stackTrace);
    }
  }

  /// Returns the next complete packet's payload, waiting for more bytes if
  /// none has fully arrived yet.
  Future<Uint8List> readPacket() {
    final buffered = _reassembler.take();
    if (buffered != null) return Future.value(buffered);

    final deadWith = _deadWith;
    if (deadWith != null) return Future.error(deadWith, _deadTrace);

    final completer = Completer<Uint8List>();
    _waiting = completer;
    return completer.future;
  }

  void write(Uint8List bytes) => _socket.add(bytes);

  Future<void> flush() => _socket.flush();

  /// Pauses delivery so the underlying socket can be handed to
  /// [SecureSocket.secure] without this channel racing it for bytes.
  /// [MySqlConnection.connect] never reads from this channel again after
  /// calling this -- a fresh one is built over the resulting secure socket.
  void pauseForUpgrade() => _subscription.pause();

  Future<void> destroy() async {
    await _subscription.cancel();
    _socket.destroy();
  }
}

/// Drives the handshake-response half of [authenticate] over a
/// [_PacketChannel], threading the MySQL packet sequence id through both
/// directions.
///
/// Sending advances the id by however many physical packets [send] actually
/// wrote, carried in [nextSequenceId] across the call: this transport
/// outlives at most one TLS upgrade (the one [MySqlConnection.connect]
/// performs before authenticating), and after that upgrade the channel
/// underneath is a fresh one whose own bookkeeping starts back at `0`, so
/// the id cannot be recovered from the channel alone. Receiving instead
/// reads the id the server actually used off the channel it just read from,
/// which is always accurate for whichever channel is current.
final class _ConnectionAuthTransport implements AuthTransport {
  _ConnectionAuthTransport(
    this._channel, {
    required this.isSecure,
    required this.nextSequenceId,
  });

  final _PacketChannel _channel;

  @override
  final bool isSecure;

  /// The class doc comment on [_ConnectionAuthTransport] explains why this
  /// is carried explicitly rather than read off [_channel] on every call.
  int nextSequenceId;

  @override
  Future<void> send(Uint8List payload) async {
    final packets = framePackets(payload, nextSequenceId);
    for (final packet in packets) {
      _channel.write(packet);
    }
    await _channel.flush();
    nextSequenceId = (nextSequenceId + packets.length) & 0xff;
  }

  @override
  Future<Uint8List> receive() async {
    final payload = await _channel.readPacket();
    nextSequenceId = (_channel.lastSequenceId + 1) & 0xff;
    return payload;
  }
}

/// The [ResponseReader] handed to a [MySqlConnection.exchange] call: reads
/// whatever packets the command's reply needs, straight off the channel.
/// Nothing about a reply shape is decided here -- only the caller's
/// `readResponse` knows how many packets to ask for.
final class _ExchangeResponseReader implements ResponseReader {
  _ExchangeResponseReader(this._channel);

  final _PacketChannel _channel;

  @override
  Future<Uint8List> next() => _channel.readPacket();
}
