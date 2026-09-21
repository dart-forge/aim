import 'package:aim_deno/src/base_path.dart';
import 'package:test/test.dart';

void main() {
  group('stripBasePath', () {
    test('removes the base path', () {
      expect(stripBasePath('/my_api/users/42', '/my_api'), '/users/42');
    });

    test('a bare base path becomes the root', () {
      expect(stripBasePath('/my_api', '/my_api'), '/');
      expect(stripBasePath('/my_api/', '/my_api'), '/');
    });

    test('accepts a base path written without the leading slash', () {
      expect(stripBasePath('/my_api/users/42', 'my_api'), '/users/42');
    });

    test('leaves the path alone when there is no base path', () {
      expect(stripBasePath('/users/42', null), '/users/42');
      expect(stripBasePath('/users/42', ''), '/users/42');
    });

    test('leaves the path alone when it does not start with the base path', () {
      expect(stripBasePath('/other/users/42', '/my_api'), '/other/users/42');
    });

    test('does not strip a partial segment match', () {
      // '/my_api_v2' must not become '_v2'.
      expect(stripBasePath('/my_api_v2/users', '/my_api'), '/my_api_v2/users');
    });
  });

  group('stripUriBasePath', () {
    test('keeps the query string', () {
      expect(
        stripUriBasePath(
          Uri.parse('/my_api/users/42?q=1'),
          '/my_api',
        ).toString(),
        '/users/42?q=1',
      );
    });

    test('keeps the fragment', () {
      expect(
        stripUriBasePath(
          Uri.parse('/my_api/users/42#frag'),
          '/my_api',
        ).toString(),
        '/users/42#frag',
      );
    });

    test('keeps both the query string and the fragment', () {
      expect(
        stripUriBasePath(
          Uri.parse('/my_api/users/42?q=1#frag'),
          '/my_api',
        ).toString(),
        '/users/42?q=1#frag',
      );
    });

    test('leaves the URL alone when there is no base path', () {
      final url = Uri.parse('/users/42?q=1#frag');
      expect(stripUriBasePath(url, null), url);
    });
  });
}
