import 'package:aim_core/aim_core.dart';
import 'package:test/test.dart';

void main() {
  group('Aim.all()', () {
    test('registers exactly one route with the "*" sentinel method', () {
      final app = Aim();
      app.all('/webhook', (c) async => c.text('ok'));

      expect(app.routes, hasLength(1));
      expect(app.routes[0].method, equals('*'));
      expect(app.routes[0].path, equals('/webhook'));
    });

    test('returns the app for chaining', () {
      final app = Aim();
      final result = app.all('/webhook', (c) async => c.text('ok'));

      expect(result, same(app));
    });

    test(
      'answers every method Aim has a named method for, and one it does not',
      () async {
        final app = Aim();
        app.all('/webhook', (c) async => c.text('received: ${c.req.method}'));

        for (final method in [
          'GET',
          'POST',
          'PUT',
          'DELETE',
          'PATCH',
          'HEAD',
          'OPTIONS',
          'TRACE',
        ]) {
          final response = await app.handle(
            Request(method, Uri.parse('http://localhost/webhook')),
          );
          expect(response.statusCode, equals(200));
          expect(await response.readAsString(), equals('received: $method'));
        }
      },
    );

    test('a get declared before an all on the same path handles GET, '
        'the all handles the rest', () async {
      final app = Aim();
      app.get('/resource', (c) async => c.text('from get'));
      app.all('/resource', (c) async => c.text('from all'));

      final getResponse = await app.handle(
        Request('GET', Uri.parse('http://localhost/resource')),
      );
      expect(await getResponse.readAsString(), equals('from get'));

      final postResponse = await app.handle(
        Request('POST', Uri.parse('http://localhost/resource')),
      );
      expect(await postResponse.readAsString(), equals('from all'));
    });

    test('an all declared before a get on the same path handles GET too, '
        'because first match wins', () async {
      final app = Aim();
      app.all('/resource', (c) async => c.text('from all'));
      app.get('/resource', (c) async => c.text('from get'));

      final getResponse = await app.handle(
        Request('GET', Uri.parse('http://localhost/resource')),
      );
      expect(await getResponse.readAsString(), equals('from all'));

      final postResponse = await app.handle(
        Request('POST', Uri.parse('http://localhost/resource')),
      );
      expect(await postResponse.readAsString(), equals('from all'));
    });

    test('an all inside a sub-app mounted with route() matches every '
        'method under the prefix', () async {
      final api = Aim();
      api.all('/ping', (c) async => c.text('pong: ${c.req.method}'));

      final app = Aim();
      app.route('/api', api);

      for (final method in ['GET', 'POST', 'TRACE']) {
        final response = await app.handle(
          Request(method, Uri.parse('http://localhost/api/ping')),
        );
        expect(response.statusCode, equals(200));
        expect(await response.readAsString(), equals('pong: $method'));
      }
    });

    test('notFound still answers a path no route matches, with an all '
        'registered on a different path', () async {
      final app = Aim();
      app.all('/webhook', (c) async => c.text('ok'));

      final response = await app.handle(
        Request('GET', Uri.parse('http://localhost/elsewhere')),
      );

      expect(response.statusCode, equals(404));
      expect(await response.readAsString(), equals('Not Found'));
    });
  });
}
