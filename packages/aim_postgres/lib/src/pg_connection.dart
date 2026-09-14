import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:aim_postgres/src/types/command_complete_tag.dart';
import 'package:aim_postgres/src/types/notice_message.dart';
import 'package:aim_postgres/src/types/parameter_encoder.dart';
import 'package:aim_postgres/src/types/query_result_decoder.dart';
import 'package:aim_postgres/src/util.dart';
import 'package:crypto/crypto.dart';

/// PostgreSQL wire protocol message types.
///
/// Each message type in the PostgreSQL protocol is identified by a single
/// character code. This enum provides a type-safe way to work with these codes.
enum PostgresMessageType {
  /// Authentication request or response ('R')
  authentication('R'),

  /// Server parameter status ('S')
  parameterStatus('S'),

  /// Backend key data for cancellation ('K')
  backendKeyData('K'),

  /// Ready for query ('Z')
  readyForQuery('Z'),

  /// Error response ('E')
  errorResponse('E'),

  /// Row description (column metadata) ('T')
  rowDescription('T'),

  /// Data row ('D')
  dataRow('D'),

  /// Command completion ('C')
  commandComplete('C'),

  /// Parse command ('P')
  parse('P'),

  /// Parse completion ('1')
  parseComplete('1'),

  /// Bind completion ('2')
  bindComplete('2'),

  /// No data available ('n')
  noData('n'),

  /// Notice response ('N')
  noticeResponse('N'),

  /// Unknown message type ('?')
  unknown('?');

  /// The single-character message type code
  final String code;

  const PostgresMessageType(this.code);

  /// Creates a [PostgresMessageType] from a message type code.
  ///
  /// Returns [PostgresMessageType.unknown] if the code is not recognized.
  static PostgresMessageType fromCode(String code) {
    return PostgresMessageType.values.firstWhere(
      (e) => e.code == code,
      orElse: () => PostgresMessageType.unknown,
    );
  }
}

/// Result of a query execution.
///
/// Contains the column metadata and row data returned from a PostgreSQL query.
class QueryResult {
  /// Creates a query result with the given [columns] and [rows].
  QueryResult({
    required this.columns,
    required this.rows,
    this.affectedRows = 0,
  });

  /// Column metadata including names, types, and other attributes.
  final List<Map<String, dynamic>> columns;

  /// Row data as a list of lists, where each inner list represents a row.
  /// Cell values are decoded Dart values (see `PgTypeDecoder`). When a
  /// Simple Query ran several `;`-separated statements, these are the rows
  /// of the LAST row-returning statement only.
  final List<List<dynamic>> rows;

  /// Rows affected as reported by CommandComplete (`INSERT 0 3` → 3). When a
  /// Simple Query ran several statements this is the sum over all of them.
  /// Commands that report no count (DDL, `BEGIN`, ...) contribute 0.
  final int affectedRows;

  /// Converts row data to a list of maps.
  ///
  /// Each map represents a row with column names as keys and cell values
  /// as values.
  List<Map<String, dynamic>> toMaps() {
    return rows.map((row) {
      final map = <String, dynamic>{};
      for (var i = 0; i < columns.length; i++) {
        map[columns[i]['name'] as String] = row[i];
      }
      return map;
    }).toList();
  }
}

/// Exception thrown when a query execution fails.
class QueryException implements Exception {
  /// Creates a query exception with the given error [message].
  QueryException(this.message);

  /// The error message from PostgreSQL.
  final String message;

  @override
  String toString() => 'QueryException: $message';
}

/// PostgreSQL authentication types.
///
/// Represents the various authentication methods supported by PostgreSQL.
enum PostgresAuthenticationType {
  /// Authentication successful (0)
  ok(0),

  /// Cleartext password authentication (3)
  cleartextPassword(3),

  /// MD5 password authentication (5)
  md5Password(5),

  /// SASL authentication (10)
  sasl(10),

  /// SASL Continue (11)
  saslContinue(11),

  /// SASL Final (12)
  saslFinal(12),

  /// GSSAPI authentication (7)
  gss(7),

  /// GSSAPI continue (8)
  gssContinue(8),

  /// SSPI authentication (9)
  sspi(9),

  /// Unknown authentication type (-1)
  unknown(-1);

  const PostgresAuthenticationType(this.code);

  /// The numeric authentication type code.
  final int code;

  /// Creates a [PostgresAuthenticationType] from an authentication code.
  ///
  /// Returns [PostgresAuthenticationType.unknown] if the code is not recognized.
  static PostgresAuthenticationType fromCode(int code) {
    return PostgresAuthenticationType.values.firstWhere(
      (type) => type.code == code,
      orElse: () => PostgresAuthenticationType.unknown,
    );
  }
}

/// PostgreSQL SSL connection modes.
///
/// Defines the various SSL/TLS connection modes supported by PostgreSQL.
enum PostgresSslMode {
  /// No SSL connection
  disable,

  /// SSL if server supports it (currently behaves same as prefer)
  allow,

  /// SSL required, certificate verification skipped
  require,

  /// Prefer SSL, fallback to plaintext if not supported
  prefer,

  /// SSL required, verify CA certificate
  verifyCa,

  /// SSL required, verify CA certificate and hostname
  verifyFull;

  /// Creates a [PostgresSslMode] from a string representation.
  ///
  /// Valid values are: disable, allow, require, prefer, verify-ca, verify-full.
  /// Throws an [Exception] if the mode string is not recognized.
  static PostgresSslMode fromString(String mode) {
    switch (mode.toLowerCase()) {
      case 'disable':
        return PostgresSslMode.disable;
      case 'allow':
        return PostgresSslMode.allow;
      case 'require':
        return PostgresSslMode.require;
      case 'prefer':
        return PostgresSslMode.prefer;
      case 'verify-ca':
        return PostgresSslMode.verifyCa;
      case 'verify-full':
        return PostgresSslMode.verifyFull;
      default:
        throw Exception('Unknown SSL mode: $mode');
    }
  }
}

/// Low-level PostgreSQL connection implementation.
///
/// This class handles the PostgreSQL wire protocol communication, including
/// authentication, SSL/TLS, and query execution using both Simple and Extended
/// Query protocols.
///
/// Most users should use [PostgresDatabase] instead of this class directly.
class PostgresConnection {
  PostgresConnection._(
    this._uri,
    this._socket,
    this._iterator,
    this._messageBuffer,
  );

  final Uri _uri;
  final Socket _socket;
  final StreamIterator<Uint8List> _iterator;
  final BytesBuilder _messageBuffer;

  // SCRAM-SHA-256 authentication state
  String? _clientNonce;
  String? _clientFirstMessageBare;

  // Backend key data for cancellation (not yet used)
  int? _processId;
  Uint8List? _secretKey;

  // NoticeResponse stream
  final StreamController<NoticeMessage> _noticeController =
      StreamController<NoticeMessage>.broadcast();
  Stream<NoticeMessage> get noticeMessage => _noticeController.stream;

  /// Chain that serializes query round-trips on this connection. The wire
  /// protocol is strictly request/response, so two in-flight queries would
  /// corrupt each other's message streams.
  Future<void> _tail = Future<void>.value();

  bool _isBroken = false;
  bool _isClosed = false;
  String _transactionStatus = 'I';

  /// `true` once sending a request or reading the response up to
  /// ReadyForQuery failed (socket error, unexpected end of stream,
  /// malformed message), or once [ping] failed. Any failure after the full
  /// response was received — a server-reported [QueryException], a
  /// [PostgresDecodeException], or any other problem found while parsing
  /// the already-buffered messages — leaves this false: the server
  /// returned ReadyForQuery, so the connection is intact (A-046).
  bool get isBroken => _isBroken;

  /// `true` once [close] has been called.
  bool get isClosed => _isClosed;

  /// Transaction status from the last ReadyForQuery: 'I' idle, 'T' in a
  /// transaction, 'E' in a failed transaction.
  String get transactionStatus => _transactionStatus;

  /// `true` while the server reports an open (or failed) transaction.
  bool get inTransaction => _transactionStatus != 'I';

  /// Runs [action] after every previously scheduled action on this
  /// connection has finished.
  Future<T> _serialized<T>(Future<T> Function() action) {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return previous.then((_) => action()).whenComplete(done.complete);
  }

  /// Sends a request via [send], then reads until ReadyForQuery and parses
  /// the result. Only a send/receive failure (the socket may be left
  /// mid-message) marks the connection broken; any failure while parsing
  /// the already-buffered response leaves it healthy.
  Future<QueryResult> _roundTrip(Future<void> Function() send) {
    return _serialized(() async {
      final List<Uint8List> messages;
      try {
        await send();
        messages = await _receiveUntilReady();
      } catch (_) {
        // The socket may be mid-message: never reuse this connection.
        _isBroken = true;
        rethrow;
      }
      // Everything below runs with the socket at a message boundary
      // (ReadyForQuery consumed), so no failure here can break the
      // connection: server errors (QueryException), decode failures
      // (PostgresDecodeException) and protocol-shape surprises all leave it
      // healthy and reusable.
      // The last message is ReadyForQuery; its single payload byte is the
      // backend transaction status ('I' / 'T' / 'E').
      final last = messages.last;
      if (String.fromCharCode(last[0]) ==
              PostgresMessageType.readyForQuery.code &&
          last.length > 5) {
        _transactionStatus = String.fromCharCode(last[5]);
      }
      return parseQueryResult(messages);
    });
  }

  /// Cheap liveness probe used by the connection pool before reusing an
  /// idle connection.
  Future<bool> ping() async {
    try {
      await sendSimpleQuery('SELECT 1');
      return true;
    } catch (_) {
      _isBroken = true;
      return false;
    }
  }

  /// Establishes a connection to a PostgreSQL database.
  ///
  /// The [connectionString] should be in the format:
  /// `postgresql://username:password@host:port/database?sslmode=mode&sslrootcert=/path/to/ca.crt`
  ///
  /// Supported SSL modes: disable, allow, prefer, require, verify-ca, verify-full
  ///
  /// Example:
  /// ```dart
  /// final conn = await PostgresConnection.connect(
  ///   'postgresql://user:pass@localhost:5432/mydb?sslmode=require',
  /// );
  /// ```
  static Future<PostgresConnection> connect(String connectionString) async {
    final uri = Uri.parse(connectionString);
    final socket = await Socket.connect(uri.host, uri.port);
    final iterator = StreamIterator<Uint8List>(socket);
    final messageBuffer = BytesBuilder();

    PostgresConnection conn = PostgresConnection._(
      uri,
      socket,
      iterator,
      messageBuffer,
    );

    final sslMode = uri.queryParameters['sslmode'] ?? 'disable';
    final pgSslMode = PostgresSslMode.fromString(sslMode);
    if (pgSslMode != PostgresSslMode.disable) {
      final caFile = uri.queryParameters['sslrootcert'];
      final secureSocket = await conn.enableSsl(pgSslMode, caFile: caFile);
      conn = PostgresConnection._(
        uri,
        secureSocket,
        StreamIterator<Uint8List>(secureSocket),
        BytesBuilder(),
      );
    }

    await conn._authenticate();

    return conn;
  }

  /// Receives messages until a ReadyForQuery message is received.
  ///
  /// Returns a list of all received messages, including the final
  /// ReadyForQuery message. This is used to collect all response messages
  /// for a query execution.
  Future<List<Uint8List>> _receiveUntilReady() async {
    final messages = <Uint8List>[];

    while (true) {
      final message = await _receiveMessage(_iterator, _messageBuffer);
      messages.add(message);

      final messageType = PostgresMessageType.fromCode(
        String.fromCharCode(message[0]),
      );

      if (messageType == PostgresMessageType.noticeResponse) {
        final notice = NoticeMessage.fromPayload(message.sublist(5));
        _noticeController.add(notice);
        continue;
      }

      if (messageType == PostgresMessageType.readyForQuery) {
        break;
      }
    }

    return messages;
  }


  Future<Uint8List> _receiveMessage(
    StreamIterator<Uint8List> iterator,
    BytesBuilder messageBuffer,
  ) async {
    while (true) {
      final bytes = messageBuffer.toBytes();

      if (bytes.length < 5) {
        final hasNext = await iterator.moveNext();
        if (!hasNext) {
          throw Exception('Stream ended unexpectedly');
        }
        messageBuffer.add(iterator.current);
        continue;
      }

      final length = bytesToInt32(bytes.sublist(1, 5));
      final totalLength = 1 + length;

      if (bytes.length < totalLength) {
        final hasNext = await iterator.moveNext();
        if (!hasNext) {
          throw Exception('Stream ended unexpectedly');
        }
        messageBuffer.add(iterator.current);
        continue;
      }

      final message = bytes.sublist(0, totalLength);
      messageBuffer.clear();
      if (bytes.length > totalLength) {
        messageBuffer.add(bytes.sublist(totalLength));
      }

      return message;
    }
  }

  /// Cancel query in progress.
  Future<void> cancelQuery() async {
    if (_processId == null || _secretKey == null) {
      throw Exception('Cannot cancel query: no backend key data available');
    }

    final cancelSocket = await Socket.connect(_uri.host, _uri.port);
    try {
      final builder = BytesBuilder();
      final payload = BytesBuilder();

      payload.add(int32Bytes(80877102));
      payload.add(int32Bytes(_processId!));
      payload.add(_secretKey!);

      final messageLength = 4 + payload.length;
      builder.add(int32Bytes(messageLength));
      builder.add(payload.toBytes());

      cancelSocket.add(builder.toBytes());
      await cancelSocket.flush();
    } catch (_) {
      rethrow;
    } finally {
      await cancelSocket.close();
    }
  }

  /// Closes the connection to the PostgreSQL database.
  ///
  /// Sends a Terminate message to the server to gracefully close the connection,
  /// then cancels the stream iterator and closes the underlying socket.
  Future<void> close() async {
    _isClosed = true;
    try {
      final builder = BytesBuilder();
      builder.addByte('X'.codeUnitAt(0));
      builder.add(int32Bytes(4)); // Length of message
      _socket.add(builder.toBytes());
      await _socket.flush();
    } catch (_) {
      // Ignore errors during close
    } finally {
      await _iterator.cancel();
      _socket.destroy();
      await _noticeController.close();
    }
  }
}

/// SSL/TLS connection support for PostgreSQL.
///
/// This extension provides SSL/TLS handshake and certificate verification
/// functionality for PostgreSQL connections.
extension PostgresConnectionSsl on PostgresConnection {
  /// Enables SSL/TLS encryption for the connection.
  ///
  /// Sends an SSL request to the PostgreSQL server and upgrades to a secure
  /// connection if the server supports it. The behavior depends on [sslMode]:
  ///
  /// - [PostgresSslMode.disable]: No SSL (this method should not be called)
  /// - [PostgresSslMode.allow]: SSL preferred (currently same as prefer)
  /// - [PostgresSslMode.prefer]: Prefer SSL, fallback to plaintext
  /// - [PostgresSslMode.require]: Require SSL, skip certificate verification
  /// - [PostgresSslMode.verifyCa]: Require SSL with CA verification
  /// - [PostgresSslMode.verifyFull]: Require SSL with CA and hostname verification
  ///
  /// The [caFile] parameter specifies the path to a CA certificate file for
  /// certificate verification. Required when [sslMode] is verifyCa or verifyFull.
  ///
  /// Returns the upgraded [SecureSocket] or the original [Socket] if SSL is
  /// not supported and [sslMode] allows plaintext fallback.
  ///
  /// Throws an [Exception] if:
  /// - Server doesn't support SSL when [sslMode] requires it
  /// - [caFile] is not provided when certificate verification is required
  /// - SSL request is rejected by the server
  Future<Socket> enableSsl(PostgresSslMode sslMode, {String? caFile}) async {
    final builder = BytesBuilder();
    builder.add(int32Bytes(8));
    builder.add(int32Bytes(80877103));

    _socket.add(builder.toBytes());
    await _socket.flush();

    final hasNext = await _iterator.moveNext();
    if (!hasNext) {
      throw Exception('No response from server for SSL request');
    }

    final response = _iterator.current;
    if (response.isEmpty) {
      throw Exception('SSL not supported by server');
    }

    if (response[0] == 'S'.codeUnitAt(0)) {
      // Control certificate verification based on SSL mode
      final shouldVerify =
          sslMode == PostgresSslMode.verifyCa ||
          sslMode == PostgresSslMode.verifyFull;

      if (shouldVerify && caFile != null) {
        // Enable CA certificate verification
        // Note: verify-ca and verify-full currently behave the same (both verify hostname)
        // because Dart's SecureSocket performs hostname verification by default when host is provided
        final context = SecurityContext(withTrustedRoots: false);
        context.setTrustedCertificates(caFile);

        return await SecureSocket.secure(
          _socket,
          host: _uri.host,
          context: context,
        );
      } else if (shouldVerify && caFile == null) {
        // verify-ca/verify-full specified but no CA certificate provided
        throw Exception('SSL mode $sslMode requires sslrootcert parameter');
      } else {
        // require/prefer/allow - skip certificate verification
        // Note: allow is supposed to prefer plaintext but currently behaves same as prefer
        return await SecureSocket.secure(
          _socket,
          host: _uri.host,
          onBadCertificate: (_) => true,
        );
      }
    }

    if (response[0] == 'N'.codeUnitAt(0)) {
      // SSL not supported by server
      if (sslMode == PostgresSslMode.require ||
          sslMode == PostgresSslMode.verifyCa ||
          sslMode == PostgresSslMode.verifyFull) {
        throw Exception('SSL required but not supported by server');
      }
      return _socket; // Continue with plaintext for prefer/allow
    }

    if (response[0] == 'E'.codeUnitAt(0)) {
      throw Exception('SSL request rejected by server');
    }

    throw Exception('Unexpected response to SSL request: ${response[0]}');
  }
}

/// Authentication support for PostgreSQL.
///
/// This extension provides authentication functionality including cleartext
/// password and MD5 password authentication.
extension PostgresConnectionAuthenticator on PostgresConnection {
  /// Performs the authentication handshake with PostgreSQL.
  ///
  /// Sends a startup message and handles the authentication response from
  /// the server. Supports cleartext and MD5 password authentication.
  Future<void> _authenticate() async {
    // Send startup message
    final parts = _uri.userInfo.split(':');
    final username = parts[0];

    final startupMessage = BytesBuilder();
    final version = 196608; // Protocol version 3.0

    final params = {'user': username, 'database': _uri.path.substring(1)};
    final paramsBytes = BytesBuilder();
    for (final entry in params.entries) {
      paramsBytes.add(utf8.encode(entry.key));
      paramsBytes.addByte(0);
      paramsBytes.add(utf8.encode(entry.value));
      paramsBytes.addByte(0);
    }
    paramsBytes.addByte(0); // Terminating null byte

    final messageLength =
        4 + 4 + paramsBytes.length; // Length + version + params

    startupMessage.add(int32Bytes(messageLength));
    startupMessage.add(int32Bytes(version));
    startupMessage.add(paramsBytes.toBytes());

    _socket.add(startupMessage.toBytes());
    await _socket.flush();

    // Receive messages until ReadyForQuery (password may need to be sent)
    while (true) {
      final message = await _receiveMessage(_iterator, _messageBuffer);

      final messageType = PostgresMessageType.fromCode(
        String.fromCharCode(message[0]),
      );

      // Handle error responses
      if (messageType == PostgresMessageType.errorResponse) {
        final errorMessage = _parseErrorResponse(message.sublist(5));
        throw QueryException(errorMessage);
      }

      // Handle authentication messages (password may be required)
      if (messageType == PostgresMessageType.authentication) {
        final payload = message.sublist(5);
        await _handleAuthentication(payload, _socket);
      }

      if (messageType == PostgresMessageType.backendKeyData) {
        _processId = bytesToInt32(message.sublist(5, 9));
        _secretKey = message.sublist(9);
      }

      if (messageType == PostgresMessageType.readyForQuery) {
        break;
      }
    }
  }

  /// Extracts error message from ErrorResponse message.
  ///
  /// Parses the error response fields and returns the error message.
  /// Prefers the 'M' (message) field, falls back to 'S' (severity).
  String _parseErrorResponse(Uint8List payload) {
    var offset = 0;
    final fields = <String, String>{};

    // Parse fields sequentially (Byte1 type code + null-terminated string)
    while (offset < payload.length && payload[offset] != 0) {
      final fieldType = String.fromCharCode(payload[offset]);
      offset++;

      // Find null-terminated string
      final endIndex = payload.indexOf(0, offset);
      if (endIndex == -1) break;

      final fieldValue = utf8.decode(payload.sublist(offset, endIndex));
      fields[fieldType] = fieldValue;

      offset = endIndex + 1; // Move past null byte
    }

    // Prefer 'M' field (message), fallback to 'S' (severity)
    return fields['M'] ?? fields['S'] ?? 'Unknown error';
  }

  /// Handles authentication based on the server's authentication request.
  ///
  /// Supports cleartext password, MD5 password, and SCRAM authentication.
  Future<void> _handleAuthentication(Uint8List payload, Socket socket) async {
    final authTypeCode = bytesToInt32(payload.sublist(0, 4));
    final authType = PostgresAuthenticationType.fromCode(authTypeCode);

    switch (authType) {
      case PostgresAuthenticationType.ok:
        // Authentication successful
        break;
      case PostgresAuthenticationType.cleartextPassword:
        await _sendCleartextPasswordMessage(_uri.userInfo.split(':')[1]);
        break;
      case PostgresAuthenticationType.md5Password:
        await _sendMd5PasswordMessage(
          _uri.userInfo.split(':')[0],
          _uri.userInfo.split(':')[1],
          payload,
        );
      case PostgresAuthenticationType.sasl:
        await _sendSaslInitialResponse(payload);
      case PostgresAuthenticationType.saslContinue:
        await _sendSaslResponse(payload);
      case PostgresAuthenticationType.saslFinal:
        // Server sends final verification - we can optionally verify it
        // For now, just accept it (authentication is complete)
        break;
      case PostgresAuthenticationType.gss:
        throw UnimplementedError('GSSAPI authentication not yet supported');
      case PostgresAuthenticationType.gssContinue:
        throw UnimplementedError('GSSAPI continue not yet supported');
      case PostgresAuthenticationType.sspi:
        throw UnimplementedError('SSPI authentication not yet supported');
      case PostgresAuthenticationType.unknown:
        throw Exception('Unsupported authentication type: $authTypeCode');
    }
  }

  /// Sends a cleartext password message to the server.
  Future<void> _sendCleartextPasswordMessage(String password) async {
    final builder = BytesBuilder();

    builder.addByte('p'.codeUnitAt(0));

    final passwordBytes = utf8.encode(password);
    final messageLength =
        4 + passwordBytes.length + 1; // length + password + null

    builder.add(int32Bytes(messageLength));
    builder.add(passwordBytes);
    builder.addByte(0); // null terminator

    _socket.add(builder.toBytes());
    await _socket.flush();
  }

  /// Sends an MD5 password message to the server.
  ///
  /// MD5 password = md5(md5(password + username) + salt)
  Future<void> _sendMd5PasswordMessage(
    String username,
    String password,
    Uint8List payload,
  ) async {
    final builder = BytesBuilder();
    builder.addByte('p'.codeUnitAt(0));

    final inner = Uint8List.fromList(
      md5.convert(utf8.encode(password + username)).bytes,
    );
    final innerHex = bytesToHex(inner);

    final combined = BytesBuilder();
    combined.add(utf8.encode(innerHex));

    final salt = payload.sublist(4, 8);
    combined.add(salt);

    final outer = Uint8List.fromList(md5.convert(combined.toBytes()).bytes);
    final md5Password = 'md5${bytesToHex(outer)}';

    final passwordBytes = utf8.encode(md5Password);
    final messageLength =
        4 + passwordBytes.length + 1; // length + password + null

    builder.add(int32Bytes(messageLength));
    builder.add(passwordBytes);
    builder.addByte(0); // null terminator

    _socket.add(builder.toBytes());
    await _socket.flush();
  }

  /// Sends a SASL initial response for SCRAM-SHA-256 authentication.
  Future<void> _sendSaslInitialResponse(Uint8List payload) async {
    final mechanisms = <String>[];
    var offset = 4;

    while (offset < payload.length) {
      final endIndex = payload.indexOf(0, offset);
      if (endIndex == -1 || endIndex == offset) break;

      mechanisms.add(utf8.decode(payload.sublist(offset, endIndex)));
      offset = endIndex + 1;
    }

    // Check for SCRAM-SHA-256 support
    if (!mechanisms.any((m) => m.startsWith('SCRAM-SHA-256'))) {
      throw Exception(
        'SCRAM-SHA-256 not supported. Available: ${mechanisms.join(", ")}',
      );
    }

    // Generate client nonce
    final random = Random.secure();
    final nonceBytes = List<int>.generate(18, (_) => random.nextInt(256));
    _clientNonce = base64.encode(nonceBytes);

    final username = _uri.userInfo.split(':')[0];
    _clientFirstMessageBare = 'n=$username,r=$_clientNonce';
    final clientFirstMessage = 'n,,$_clientFirstMessageBare';

    final builder = BytesBuilder();
    builder.addByte('p'.codeUnitAt(0));

    final messagePayload = BytesBuilder();

    // SASL mechanism name (null-terminated)
    messagePayload.add(utf8.encode('SCRAM-SHA-256'));
    messagePayload.addByte(0);

    // Client first message length and data
    final clientFirstBytes = utf8.encode(clientFirstMessage);
    messagePayload.add(int32Bytes(clientFirstBytes.length));
    messagePayload.add(clientFirstBytes);

    final messageLength = 4 + messagePayload.length;
    builder.add(int32Bytes(messageLength));
    builder.add(messagePayload.toBytes());

    _socket.add(builder.toBytes());
    await _socket.flush();
  }

  /// Sends a SASL response for SCRAM-SHA-256 authentication.
  Future<void> _sendSaslResponse(Uint8List payload) async {
    final serverFirstMessage = utf8.decode(payload.sublist(4));

    // Parse server-first-message: r=nonce,s=salt,i=iterations
    final serverParams = _parseSaslMessage(serverFirstMessage);
    final serverNonce = serverParams['r']!;
    final salt = base64.decode(serverParams['s']!);
    final iterations = int.parse(serverParams['i']!);

    // Verify server nonce starts with client nonce
    if (!serverNonce.startsWith(_clientNonce!)) {
      throw Exception('Server nonce does not start with client nonce');
    }

    // Calculate client proof
    final password = _uri.userInfo.split(':')[1];
    final clientProof = _calculateClientProof(
      password,
      salt,
      iterations,
      _clientFirstMessageBare!,
      serverFirstMessage,
      serverNonce,
    );

    // Build client-final-message
    final channelBinding = base64.encode(utf8.encode('n,,'));
    final clientFinalMessageWithoutProof = 'c=$channelBinding,r=$serverNonce';
    final clientFinalMessage = '$clientFinalMessageWithoutProof,p=$clientProof';

    // Send SASL response
    final builder = BytesBuilder();
    builder.addByte('p'.codeUnitAt(0));

    final messageBytes = utf8.encode(clientFinalMessage);
    final messageLength = 4 + messageBytes.length;

    builder.add(int32Bytes(messageLength));
    builder.add(messageBytes);

    _socket.add(builder.toBytes());
    await _socket.flush();
  }

  /// Parses a SASL message into key-value pairs.
  Map<String, String> _parseSaslMessage(String message) {
    final result = <String, String>{};
    for (final part in message.split(',')) {
      if (part.length >= 2 && part[1] == '=') {
        result[part[0]] = part.substring(2);
      }
    }
    return result;
  }

  /// Calculates the client proof for SCRAM-SHA-256.
  String _calculateClientProof(
    String password,
    List<int> salt,
    int iterations,
    String clientFirstMessageBare,
    String serverFirstMessage,
    String serverNonce,
  ) {
    // 1. SaltedPassword = PBKDF2(password, salt, iterations)
    final saltedPassword = _pbkdf2Sha256(
      utf8.encode(password),
      salt,
      iterations,
    );

    // 2. ClientKey = HMAC(SaltedPassword, "Client Key")
    final clientKey = _hmacSha256(saltedPassword, utf8.encode('Client Key'));

    // 3. StoredKey = SHA256(ClientKey)
    final storedKey = sha256.convert(clientKey).bytes;

    // 4. AuthMessage
    final channelBinding = base64.encode(utf8.encode('n,,'));
    final clientFinalWithoutProof = 'c=$channelBinding,r=$serverNonce';
    final authMessage =
        '$clientFirstMessageBare,$serverFirstMessage,$clientFinalWithoutProof';

    // 5. ClientSignature = HMAC(StoredKey, AuthMessage)
    final clientSignature = _hmacSha256(storedKey, utf8.encode(authMessage));

    // 6. ClientProof = ClientKey XOR ClientSignature
    final clientProof = List<int>.generate(
      clientKey.length,
      (i) => clientKey[i] ^ clientSignature[i],
    );

    return base64.encode(clientProof);
  }

  /// HMAC-SHA256 helper.
  List<int> _hmacSha256(List<int> key, List<int> data) {
    final hmac = Hmac(sha256, key);
    return hmac.convert(data).bytes;
  }

  /// PBKDF2-HMAC-SHA256 implementation.
  List<int> _pbkdf2Sha256(List<int> password, List<int> salt, int iterations) {
    // PBKDF2 with HMAC-SHA256, generating 32 bytes (256 bits)
    final blockCount = 1; // For SHA256, we need 1 block of 32 bytes
    final result = <int>[];

    for (var block = 1; block <= blockCount; block++) {
      // U1 = HMAC(password, salt || INT(block))
      final blockBytes = BytesBuilder();
      blockBytes.add(salt);
      blockBytes.add(int32Bytes(block));

      var u = _hmacSha256(password, blockBytes.toBytes());
      final t = List<int>.from(u);

      // U2 through Uc
      for (var i = 1; i < iterations; i++) {
        u = _hmacSha256(password, u);
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }

      result.addAll(t);
    }

    return result.sublist(0, 32); // Return 32 bytes for SHA256
  }
}

/// Message parsing utilities for PostgreSQL wire protocol.
///
/// This extension provides functionality to parse PostgreSQL protocol messages
/// including RowDescription and DataRow messages.
extension PostgresConnectionMessageParser on PostgresConnection {
  /// Extracts query results from a sequence of messages.
  ///
  /// Parses RowDescription and DataRow messages to construct a [QueryResult].
  /// Cell decoding runs here, after the whole response (through
  /// ReadyForQuery) has been read, so a decode failure never leaves the
  /// socket mid-message.
  ///
  /// A Simple Query can carry several `;`-separated statements, each with
  /// its own RowDescription/DataRow/CommandComplete sequence. [columns] and
  /// [QueryResult.rows] reflect only the LAST row-returning statement: a new
  /// RowDescription discards any rows collected for a previous statement.
  /// [QueryResult.affectedRows] is unaffected by this — it keeps summing the
  /// CommandComplete tag of every statement.
  QueryResult parseQueryResult(List<Uint8List> messages) {
    List<Map<String, dynamic>>? columns;
    var rawRows = <List<Uint8List?>>[];
    var affectedRows = 0;

    for (final msg in messages) {
      final messageType = PostgresMessageType.fromCode(
        String.fromCharCode(msg[0]),
      );

      switch (messageType) {
        case PostgresMessageType.rowDescription:
          // A later statement in the same Simple Query: its rows replace
          // whatever the previous statement had accumulated.
          if (columns != null) rawRows = <List<Uint8List?>>[];
          columns = parseRowDescription(msg.sublist(5));
          break;
        case PostgresMessageType.dataRow:
          rawRows.add(parseDataRow(msg.sublist(5)));
          break;
        case PostgresMessageType.commandComplete:
          affectedRows += affectedRowsFromCommandTag(utf8.decode(msg.sublist(5)));
          break;
        case PostgresMessageType.errorResponse:
          throw QueryException(utf8.decode(msg.sublist(5)));
        case PostgresMessageType.parseComplete:
        case PostgresMessageType.bindComplete:
        case PostgresMessageType.noData:
        case PostgresMessageType.readyForQuery:
          // Ignore these messages
          break;
        default:
          // Ignore other messages
          break;
      }
    }

    final resolvedColumns = columns ?? const <Map<String, dynamic>>[];
    return QueryResult(
      columns: resolvedColumns,
      rows: decodeRows(resolvedColumns, rawRows),
      affectedRows: affectedRows,
    );
  }

  /// Parses a RowDescription message.
  ///
  /// Returns a list of column metadata maps containing name, type, and other
  /// attributes for each column in the result set.
  List<Map<String, dynamic>> parseRowDescription(Uint8List payload) {
    var offset = 0;

    // Number of columns
    final fieldCount = bytesToInt16(payload.sublist(offset, offset + 2));
    offset += 2;

    final columns = <Map<String, dynamic>>[];

    for (var i = 0; i < fieldCount; i++) {
      // Column name (null-terminated)
      final nameEnd = payload.indexOf(0, offset);
      final name = utf8.decode(payload.sublist(offset, nameEnd));
      offset = nameEnd + 1;

      // Table OID (4 bytes)
      final tableOid = bytesToInt32(payload.sublist(offset, offset + 4));
      offset += 4;

      // Column attribute number (2 bytes)
      final columnAttr = bytesToInt16(payload.sublist(offset, offset + 2));
      offset += 2;

      // Type OID (4 bytes)
      final typeOid = bytesToInt32(payload.sublist(offset, offset + 4));
      offset += 4;

      // Type size (2 bytes)
      final typeSize = bytesToInt16(payload.sublist(offset, offset + 2));
      offset += 2;

      // Type modifier (4 bytes)
      final typeMod = bytesToInt32(payload.sublist(offset, offset + 4));
      offset += 4;

      // Format code (2 bytes)
      final formatCode = bytesToInt16(payload.sublist(offset, offset + 2));
      offset += 2;

      columns.add({
        'name': name,
        'tableOid': tableOid,
        'columnAttr': columnAttr,
        'typeOid': typeOid,
        'typeSize': typeSize,
        'typeMod': typeMod,
        'formatCode': formatCode,
      });
    }

    return columns;
  }

  /// Parses a DataRow message.
  ///
  /// Returns the raw bytes of each cell; NULL is `null`. Conversion to Dart
  /// values happens in [parseQueryResult] via `decodeRows`, once the column
  /// types are known.
  List<Uint8List?> parseDataRow(Uint8List payload) {
    var offset = 0;

    // Number of columns
    final columnCount = bytesToInt16(payload.sublist(offset, offset + 2));
    offset += 2;

    final values = <Uint8List?>[];

    for (var i = 0; i < columnCount; i++) {
      // Value length
      final valueLength = bytesToInt32(payload.sublist(offset, offset + 4));
      offset += 4;

      if (valueLength == -1) {
        // NULL value
        values.add(null);
      } else {
        values.add(payload.sublist(offset, offset + valueLength));
        offset += valueLength;
      }
    }

    return values;
  }
}

/// Simple Query Protocol implementation.
///
/// This extension provides functionality to execute queries using PostgreSQL's
/// Simple Query Protocol (no parameter binding).
extension PostgresConnectionSimpleQuery on PostgresConnection {
  /// Executes a query and returns the result.
  ///
  /// Uses the Simple Query Protocol without parameter binding. For queries
  /// with parameters, use [sendExtendedQuery] instead.
  Future<QueryResult> sendSimpleQuery(String sql) {
    return _roundTrip(() async {
      final builder = BytesBuilder();
      builder.addByte('Q'.codeUnitAt(0));

      final sqlBytes = utf8.encode(sql);
      final messageLength = 4 + sqlBytes.length + 1; // length + SQL + null

      builder.add(int32Bytes(messageLength));
      builder.add(sqlBytes);
      builder.addByte(0); // null terminator

      _socket.add(builder.toBytes());
      await _socket.flush();
    });
  }
}

/// Extended Query Protocol implementation.
///
/// This extension provides functionality to execute parameterized queries using
/// PostgreSQL's Extended Query Protocol with parameter binding.
extension PostgresConnectionExtendedQuery on PostgresConnection {
  /// Executes a parameterized query using Extended Query Protocol.
  ///
  /// The [sql] string should use $1, $2, etc. for parameter placeholders.
  /// The [parameters] list contains the values to bind to these placeholders.
  Future<QueryResult> sendExtendedQuery(
    String sql,
    List<dynamic> parameters,
  ) {
    return _roundTrip(() async {
      await _sendParse(sql, parameters.length);
      await _sendBind(parameters);
      await _sendDescribe('P');
      await _sendExecute();
      await _sendSync();
    });
  }

  /// Sends a Parse message.
  Future<void> _sendParse(String sql, int paramCount) async {
    final builder = BytesBuilder();

    // Message type 'P'
    builder.addByte('P'.codeUnitAt(0));

    // Build payload
    final payload = BytesBuilder();

    // Prepared statement name (unnamed = "")
    payload.addByte(0);

    // SQL query (null-terminated)
    payload.add(utf8.encode(sql));
    payload.addByte(0);

    // Number of parameter type OIDs (0 = server infers types)
    payload.add(int16Bytes(0));

    // Message length (includes 4 bytes for length field itself)
    final messageLength = 4 + payload.length;
    builder.add(int32Bytes(messageLength));
    builder.add(payload.toBytes());

    _socket.add(builder.toBytes());
    await _socket.flush();
  }

  /// Sends a Bind message.
  Future<void> _sendBind(List<dynamic> parameters) async {
    final builder = BytesBuilder();

    // Message type 'B'
    builder.addByte('B'.codeUnitAt(0));

    // Build payload
    final payload = BytesBuilder();

    // Portal name (unnamed = "")
    payload.addByte(0);

    // Prepared statement name (unnamed = "")
    payload.addByte(0);

    // Parameter format code count (all text format = 0)
    payload.add(int16Bytes(0));

    // Number of parameter values
    payload.add(int16Bytes(parameters.length));

    // Each parameter value
    for (final param in parameters) {
      final encoded = _encodeParameter(param);
      if (encoded == null) {
        // NULL value
        payload.add(int32Bytes(-1));
      } else {
        payload.add(int32Bytes(encoded.length));
        payload.add(encoded);
      }
    }

    // Result column format code count (all text format = 0)
    payload.add(int16Bytes(0));

    // Message length
    final messageLength = 4 + payload.length;
    builder.add(int32Bytes(messageLength));
    builder.add(payload.toBytes());

    _socket.add(builder.toBytes());
    await _socket.flush();
  }

  /// Sends a Describe message.
  Future<void> _sendDescribe(String type) async {
    final builder = BytesBuilder();

    // Message type 'D'
    builder.addByte('D'.codeUnitAt(0));

    // Payload
    final payload = BytesBuilder();

    // 'S' = Statement, 'P' = Portal
    payload.addByte(type.codeUnitAt(0));

    // Name (unnamed = "")
    payload.addByte(0);

    // Message length
    final messageLength = 4 + payload.length;
    builder.add(int32Bytes(messageLength));
    builder.add(payload.toBytes());

    _socket.add(builder.toBytes());
    await _socket.flush();
  }

  /// Sends an Execute message.
  Future<void> _sendExecute() async {
    final builder = BytesBuilder();

    // Message type 'E'
    builder.addByte('E'.codeUnitAt(0));

    // Payload
    final payload = BytesBuilder();

    // Portal name (unnamed = "")
    payload.addByte(0);

    // Maximum number of rows (0 = unlimited)
    payload.add(int32Bytes(0));

    // Message length
    final messageLength = 4 + payload.length;
    builder.add(int32Bytes(messageLength));
    builder.add(payload.toBytes());

    _socket.add(builder.toBytes());
    await _socket.flush();
  }

  /// Sends a Sync message.
  Future<void> _sendSync() async {
    final builder = BytesBuilder();

    // Message type 'S'
    builder.addByte('S'.codeUnitAt(0));

    // Message length (no payload)
    builder.add(int32Bytes(4));

    _socket.add(builder.toBytes());
    await _socket.flush();
  }

  /// Encodes a parameter value to text format. See [encodeParameterText]
  /// for the supported types.
  Uint8List? _encodeParameter(dynamic value) => encodeParameter(value);
}
