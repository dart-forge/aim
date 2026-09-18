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
import 'dart:async';
import 'dart:io';

import 'package:aim_functions/aim_functions.dart';
import 'package:shelf/shelf.dart' as shelf;
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

  // `shelf_io.serve`'s own top-level error catching (`catchTopLevelErrors`
  // in shelf's `src/util.dart`) only installs a zone when called from the
  // *root* zone; `dart test` runs every test in its own non-root zone, so
  // inside a test it is a no-op and an async error that escapes shelf_io's
  // request-writing code (which the D-1 fix deliberately lets happen, so
  // the failure is visible to the client) would otherwise surface as a
  // spurious failure of whichever test happens to be running when the
  // write actually fails, rather than of the test that caused it. Serving
  // through this helper installs that zone ourselves, so such an error is
  // captured here — where it can be asserted on — instead of leaking out.
  Future<HttpServer> serveCapturingAsyncErrors(
    shelf.Handler handler,
    void Function(Object error, StackTrace stackTrace) onError,
  ) {
    final completer = Completer<HttpServer>();
    runZonedGuarded(() {
      shelf_io
          .serve(handler, InternetAddress.loopbackIPv4, 0)
          .then(completer.complete, onError: completer.completeError);
    }, onError);
    return completer.future;
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

    test('a response stream that fails mid-flight does not take the server '
        'down — the next request still succeeds', () async {
      // The failure is logged (checked by hand — a real dart:io stderr,
      // not a Zone, is what serve_functions.dart writes to) and, since
      // the D-1 fix, also re-signalled to shelf_io rather than swallowed:
      // the client sees the transfer break instead of a clean 200. That
      // signal escapes as an async error outside every try/catch this
      // adapter has, which is exactly what `serveCapturingAsyncErrors`
      // exists to capture (see its doc comment) instead of it corrupting
      // an unrelated test. What matters for *this* test is that none of
      // that takes the server down.
      var callCount = 0;
      final asyncErrors = <Object>[];
      final app = Aim();
      app.get('/stream-fails', (c) async {
        callCount++;
        return Response.stream(() async* {
          yield [1, 2, 3];
          throw StateError('disk went away mid-stream');
        }());
      });
      app.get('/ok', (c) async => c.text('still alive'));

      final server = await serveCapturingAsyncErrors(
        app.serveFunction(),
        (e, st) => asyncErrors.add(e),
      );
      addTearDown(() => server.close(force: true));

      try {
        final res = await get(server.port, '/stream-fails');
        await res.drain<void>();
      } catch (_) {
        // Expected: the transfer breaks once the producer throws.
      }

      expect(callCount, 1);
      expect(asyncErrors, hasLength(1));
      final res = await get(server.port, '/ok');
      expect(
        await res.transform(const SystemEncoding().decoder).join(),
        'still alive',
      );
    });

    test('a response stream that errors mid-flight never delivers bytes '
        'produced after the error', () async {
      // A producer that reports a failure and then keeps emitting — a
      // retrying reader, or a controller fed from a source that keeps
      // pushing once something has already gone wrong. Whatever this
      // adapter does about the error, it must never let bytes produced
      // *after* the failure was reported reach the client: that would be
      // a corrupted response, not merely a truncated one. See
      // `serveCapturingAsyncErrors`'s doc comment for why the server is
      // started through it rather than through `shelf_io.serve` directly.
      final controller = StreamController<List<int>>();
      unawaited(
        Future(() async {
          controller.add('A'.codeUnits);
          await Future<void>.delayed(Duration.zero);
          controller.addError(StateError('boom'));
          await Future<void>.delayed(Duration.zero);
          controller.add('B-after-error'.codeUnits);
          await Future<void>.delayed(Duration.zero);
          await controller.close();
        }),
      );

      final app = Aim();
      app.get('/leaky', (c) async => Response.stream(controller.stream));

      final asyncErrors = <Object>[];
      final server = await serveCapturingAsyncErrors(
        app.serveFunction(),
        (e, st) => asyncErrors.add(e),
      );
      addTearDown(() => server.close(force: true));

      var body = '';
      try {
        final res = await get(server.port, '/leaky');
        body = await res.transform(const SystemEncoding().decoder).join();
      } catch (_) {
        // Expected: the client observes the transfer breaking, instead
        // of receiving a response that looks complete but silently
        // carries bytes sent after the failure.
      }

      expect(body, isNot(contains('after-error')));
      expect(asyncErrors, hasLength(1));
    });
  });
}
