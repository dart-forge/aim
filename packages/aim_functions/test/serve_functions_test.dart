// Deliberately does not import `firebase_functions` — see A-067 in the
// design. `serveFunction()` only needs shelf and `aim_core`; `firebase_functions`
// is required for `runFunctions`/`onRequest`, but that lives in the
// application's own entry point, not in this adapter.
import 'package:aim_functions/aim_functions.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

void main() {
  test(
    'routes a request through the app and returns 200 with the body',
    () async {
      final app = Aim()..get('/hi', (c) async => c.text('hello'));

      final handler = app.serveFunction();
      final response = await handler(
        shelf.Request('GET', Uri.parse('https://example.com/hi')),
      );

      expect(response.statusCode, 200);
      expect(await response.readAsString(), 'hello');
    },
  );

  test('answers 404 for an unregistered path', () async {
    final app = Aim()..get('/hi', (c) async => c.text('hello'));

    final handler = app.serveFunction();
    final response = await handler(
      shelf.Request('GET', Uri.parse('https://example.com/missing')),
    );

    expect(response.statusCode, 404);
  });

  test('a handler that throws answers 500, logged by the adapter rather than '
      'aim_core (aim_core never prints)', () async {
    // No onError registered: the failure falls through to
    // serveFunction's own onUnhandledError, which is the only place in
    // this stack that is allowed to log. Whether it actually reaches
    // stderr is checked by hand in Step 3 (see the task report); a test
    // can only assert the observable HTTP behaviour.
    final app = Aim()..get('/boom', (c) async => throw StateError('boom'));

    final handler = app.serveFunction();
    final response = await handler(
      shelf.Request('GET', Uri.parse('https://example.com/boom')),
    );

    expect(response.statusCode, 500);
    expect(await response.readAsString(), contains('Internal Server Error'));
  });

  test('c.req.raw is the shelf Request', () async {
    shelf.Request? capturedRaw;
    final app = Aim()
      ..get('/', (c) async {
        capturedRaw = c.req.raw as shelf.Request?;
        return c.text('ok');
      });

    final handler = app.serveFunction();
    final request = shelf.Request('GET', Uri.parse('https://example.com/'));
    await handler(request);

    expect(capturedRaw, same(request));
  });
}
