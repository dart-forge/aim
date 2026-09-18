// Deliberately does not import `firebase_functions`. That package only
// registers a handler; everything this adapter does is a shelf handler, so
// the whole of it can be tested without Firebase. If that ever stops being
// true, the translation and the entry point have grown into each other.
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

  test('c.req.shelfRequest is the underlying shelf Request', () async {
    shelf.Request? captured;
    final app = Aim()
      ..get('/', (c) async {
        captured = c.req.shelfRequest;
        return c.text('ok');
      });

    final handler = app.serveFunction();
    final request = shelf.Request('GET', Uri.parse('https://example.com/'));
    await handler(request);

    expect(captured, same(request));
  });
}
