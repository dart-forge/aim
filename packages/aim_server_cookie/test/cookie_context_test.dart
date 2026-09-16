import 'package:aim_core/aim_core.dart';
import 'package:aim_server_cookie/aim_server_cookie.dart';
import 'package:aim_server_testing/aim_server_testing.dart';
import 'package:test/test.dart';

void main() {
  group('setCookie', () {
    test('a plain cookie produces a Set-Cookie header with only name=value, '
        'no extra attributes', () async {
      final app = Aim()
        ..get('/set', (c) async {
          c.setCookie('session_id', 'abc123');
          return c.text('set');
        });
      final client = TestClient(app);

      final response = await client.get('/set');

      expect(response.header('set-cookie'), equals('session_id=abc123'));
    });

    test(
      'every option renders in the form the Set-Cookie specification uses',
      () async {
        final app = Aim()
          ..get('/set', (c) async {
            c.setCookie(
              'session_id',
              'abc123',
              options: CookieOptions(
                path: '/admin',
                domain: '.example.com',
                maxAge: Duration(days: 7),
                expires: DateTime.utc(2015, 10, 21, 7, 28, 0),
                secure: true,
                httpOnly: true,
                sameSite: SameSite.strict,
              ),
            );
            return c.text('set');
          });
        final client = TestClient(app);

        final response = await client.get('/set');
        final cookie = response.header('set-cookie');

        expect(cookie, isNotNull);
        final parts = cookie!.split('; ');
        expect(parts.first, equals('session_id=abc123'));
        expect(parts, contains('Path=/admin'));
        expect(parts, contains('Domain=.example.com'));
        expect(parts, contains('Max-Age=604800'));
        expect(parts, contains('Expires=Wed, 21 Oct 2015 07:28:00 GMT'));
        expect(parts, contains('Secure'));
        expect(parts, contains('HttpOnly'));
        expect(parts, contains('SameSite=Strict'));
      },
    );

    for (final entry in {
      SameSite.strict: 'Strict',
      SameSite.lax: 'Lax',
      SameSite.none: 'None',
    }.entries) {
      test(
        'sameSite ${entry.key} renders as SameSite=${entry.value}',
        () async {
          final app = Aim()
            ..get('/set', (c) async {
              c.setCookie(
                'session_id',
                'abc123',
                options: CookieOptions(sameSite: entry.key),
              );
              return c.text('set');
            });
          final client = TestClient(app);

          final response = await client.get('/set');

          expect(
            response.header('set-cookie'),
            equals('session_id=abc123; SameSite=${entry.value}'),
          );
        },
      );
    }

    test('omitted boolean flags (secure/httpOnly left null) are not rendered at all', () async {
      final app = Aim()
        ..get('/set', (c) async {
          c.setCookie(
            'session_id',
            'abc123',
            options: CookieOptions(path: '/'),
          );
          return c.text('set');
        });
      final client = TestClient(app);

      final response = await client.get('/set');
      final cookie = response.header('set-cookie')!;

      expect(cookie, equals('session_id=abc123; Path=/'));
      expect(cookie, isNot(contains('Secure')));
      expect(cookie, isNot(contains('HttpOnly')));
    });

    test(
      'setting more than one cookie produces two separate Set-Cookie values, '
      'not one joined string, when read back by a real transport',
      () async {
        final app = Aim()
          ..get('/set', (c) async {
            c.setCookie('a', '1');
            c.setCookie('b', '2');
            return c.text('set');
          });
        final client = TestClient(app);

        final response = await client.get('/set');
        final raw = response.header('set-cookie');

        expect(raw, isNotNull);
        // aim_server's socket adapter splits a `\n`-joined set-cookie value
        // back into distinct Set-Cookie header lines before writing the
        // response (see aim_server/lib/src/server.dart), which is how two
        // separate setCookie() calls end up as two separate headers on the
        // wire even though this in-memory Response only has one string per
        // header name.
        final individualCookies = raw!.split('\n');
        expect(individualCookies, hasLength(2));
        expect(individualCookies[0], equals('a=1'));
        expect(individualCookies[1], equals('b=2'));
      },
    );
  });

  group('deleteCookie', () {
    test('deleting a cookie sends Max-Age=0 with an empty value, which is what '
        'a browser needs to drop it immediately', () async {
      final app = Aim()
        ..get('/logout', (c) async {
          c.deleteCookie('session_id', path: '/');
          return c.text('logged out');
        });
      final client = TestClient(app);

      final response = await client.get('/logout');
      final cookie = response.header('set-cookie');

      expect(cookie, isNotNull);
      final parts = cookie!.split('; ');
      expect(parts.first, equals('session_id='));
      expect(parts, contains('Path=/'));
      expect(parts, contains('Max-Age=0'));
    });

    test('deleteCookie forwards the same domain given to it, since a browser '
        'only drops a cookie set with a matching domain', () async {
      final app = Aim()
        ..get('/logout', (c) async {
          c.deleteCookie('session_id', path: '/', domain: '.example.com');
          return c.text('logged out');
        });
      final client = TestClient(app);

      final response = await client.get('/logout');
      final cookie = response.header('set-cookie')!;

      expect(cookie, contains('Domain=.example.com'));
    });
  });
}
