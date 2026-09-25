import 'dart:async';
import 'dart:io';

import 'package:aim_mysql/src/connection.dart';
import 'package:test/test.dart';

void main() {
  test('connect times out, and closes the socket, against a server that '
      'accepts the connection and never answers', () async {
    // connectTimeout only bounds Socket.connect itself -- once the
    // socket is open, nothing else timed out a stuck handshake before
    // queryTimeout existed, so this server -- which never writes a
    // single byte -- would otherwise hang connect() forever.
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    final accepted = Completer<Socket>();
    final serverSubscription = server.listen((socket) {
      accepted.complete(socket);
      // Never write anything back, and never close it either -- the
      // client is left waiting on a reply that will never come.
    });
    addTearDown(serverSubscription.cancel);

    final settings = MySqlConnectionSettings(
      host: server.address.address,
      port: server.port,
      user: 'nobody',
      sslMode: MySqlSslMode.disable,
      connectTimeout: const Duration(seconds: 5),
      queryTimeout: const Duration(milliseconds: 200),
    );

    final stopwatch = Stopwatch()..start();
    await expectLater(
      MySqlConnection.connect(settings),
      throwsA(isA<TimeoutException>()),
    );
    stopwatch.stop();

    expect(
      stopwatch.elapsed,
      lessThan(const Duration(seconds: 2)),
      reason:
          'it must have been queryTimeout (200ms) that fired, not '
          "connectTimeout (5s) or some other much longer wait -- Socket."
          'connect itself succeeds immediately against a real listening '
          'socket',
    );

    // The socket the fake server accepted should have been closed from
    // the client side once the timeout fired.
    final serverSideSocket = await accepted.future;
    await serverSideSocket.drain<void>().timeout(const Duration(seconds: 2));
  });
}
