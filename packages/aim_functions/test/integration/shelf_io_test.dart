// Everything in test/*.dart calls serveFunction()'s returned handler
// in-process and inspects the returned shelf.Response object directly —
// nothing ever crosses a socket. That is exactly why a defect that only
// exists in the HTTP writer (shelf_io's serialization of the Response,
// which happens after serveFunction() has already returned) was invisible:
// the in-process tests never touch that code path.
//
// This file runs the handler behind a real shelf_io HTTP server and talks
// to it with a real HTTP client, the same shape both other adapters
// (aim_server, aim_edge) use for their own test/integration/ tier.
import 'dart:io';

import 'package:aim_functions/aim_functions.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

void main() {
  late HttpClient client;

  setUp(() => client = HttpClient());
  tearDown(() => client.close(force: true));

  Future<HttpClientResponse> get(int port, String path) async {
    final req = await client.getUrl(Uri.parse('http://localhost:$port$path'));
    return req.close();
  }

  group('over a real HTTP connection (shelf_io)', () {
    test('routes a request through the app and returns 200', () async {
      final app = Aim()..get('/hi', (c) async => c.text('hello'));
      final server = await shelf_io.serve(
        app.serveFunction(),
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));

      final res = await get(server.port, '/hi');

      expect(res.statusCode, 200);
      expect(
        await res.transform(const SystemEncoding().decoder).join(),
        'hello',
      );
    });

    test('splits newline-joined Set-Cookie into separate headers', () async {
      // This is the input aim_server_cookie actually produces the second
      // time a handler calls c.setCookie(...) (it joins successive cookies
      // with '\n'), not a contrived string.
      final app = Aim();
      app.get(
        '/c',
        (c) async => Response.text(
          'ok',
          headers: {'set-cookie': 'a=1; Path=/\nb=2; Path=/'},
        ),
      );
      final server = await shelf_io.serve(
        app.serveFunction(),
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));

      final res = await get(server.port, '/c');
      await res.drain<void>();

      expect(res.statusCode, 200);
      expect(res.headers['set-cookie'], hasLength(2));
      expect(res.headers['set-cookie'], contains('a=1; Path=/'));
      expect(res.headers['set-cookie'], contains('b=2; Path=/'));
    });
  });
}
