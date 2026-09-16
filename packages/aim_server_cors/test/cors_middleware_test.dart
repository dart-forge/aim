import 'package:aim_core/aim_core.dart';
import 'package:aim_server_cors/aim_server_cors.dart';
import 'package:aim_server_testing/aim_server_testing.dart';
import 'package:test/test.dart';

void main() {
  group('cors middleware', () {
    test('simple request from an allowed specific origin gets exactly the '
        'allow-origin header it asked for, and nothing more', () async {
      final app = Aim()
        ..use(cors(CorsOptions(origin: 'https://example.com')))
        ..get('/data', (c) async => c.json({'ok': true}));
      final client = TestClient(app);

      final response = await client.get(
        '/data',
        headers: {'origin': 'https://example.com'},
      );

      expect(response.statusCode, equals(200));
      expect(
        response.header('access-control-allow-origin'),
        equals('https://example.com'),
      );
      expect(response.header('access-control-allow-credentials'), isNull);
      expect(response.header('access-control-allow-methods'), isNull);
      expect(response.header('access-control-allow-headers'), isNull);
      expect(response.header('access-control-expose-headers'), isNull);
    });

    test(
      'default cors() reflects a wildcard allow-origin for any origin',
      () async {
        final app = Aim()
          ..use(cors())
          ..get('/data', (c) async => c.json({'ok': true}));
        final client = TestClient(app);

        final response = await client.get(
          '/data',
          headers: {'origin': 'https://anything.example'},
        );

        expect(response.header('access-control-allow-origin'), equals('*'));
      },
    );

    test('a preflight request is answered directly, without running the route handler', () async {
      var handlerRan = false;
      final app = Aim()
        ..use(
          cors(
            CorsOptions(
              origin: 'https://example.com',
              allowMethods: ['GET', 'POST'],
            ),
          ),
        )
        ..options('/data', (c) async {
          handlerRan = true;
          return c.text('');
        })
        ..post('/data', (c) async {
          handlerRan = true;
          return c.json({'ok': true});
        });
      final client = TestClient(app);

      final response = await client.options(
        '/data',
        headers: {
          'origin': 'https://example.com',
          'access-control-request-method': 'POST',
          'access-control-request-headers': 'content-type',
        },
      );

      expect(handlerRan, isFalse);
      // 204 is the status browsers accept for a successful preflight.
      expect(response.statusCode, equals(204));
      expect(
        response.header('access-control-allow-origin'),
        equals('https://example.com'),
      );
      expect(
        response.header('access-control-allow-methods'),
        equals('GET, POST'),
      );
    });

    test('preflight reflects the requested headers back when allowHeaders is '
        'left at its wildcard default', () async {
      final app = Aim()
        ..use(cors(CorsOptions(origin: 'https://example.com')))
        ..post('/data', (c) async => c.json({'ok': true}));
      final client = TestClient(app);

      final response = await client.options(
        '/data',
        headers: {
          'origin': 'https://example.com',
          'access-control-request-method': 'POST',
          'access-control-request-headers': 'X-Custom-Header, Content-Type',
        },
      );

      expect(
        response.header('access-control-allow-headers'),
        equals('X-Custom-Header, Content-Type'),
      );
    });

    test('preflight sends the configured allowHeaders list rather than a '
        'reflection when allowHeaders is explicit', () async {
      final app = Aim()
        ..use(
          cors(
            CorsOptions(
              origin: 'https://example.com',
              allowHeaders: ['Content-Type', 'Authorization'],
            ),
          ),
        )
        ..post('/data', (c) async => c.json({'ok': true}));
      final client = TestClient(app);

      final response = await client.options(
        '/data',
        headers: {
          'origin': 'https://example.com',
          'access-control-request-method': 'POST',
          'access-control-request-headers': 'X-Something-Else',
        },
      );

      expect(
        response.header('access-control-allow-headers'),
        equals('Content-Type, Authorization'),
      );
    });

    test('preflight omits allow-headers entirely when the request did not ask '
        'for any headers', () async {
      final app = Aim()
        ..use(cors(CorsOptions(origin: 'https://example.com')))
        ..post('/data', (c) async => c.json({'ok': true}));
      final client = TestClient(app);

      final response = await client.options(
        '/data',
        headers: {
          'origin': 'https://example.com',
          'access-control-request-method': 'POST',
        },
      );

      expect(response.header('access-control-allow-headers'), isNull);
    });

    test(
      'a request from an origin that is not allowed gets no allow-origin '
      'header, but the route handler still runs and its body is returned',
      () async {
        var handlerRan = false;
        final app = Aim()
          ..use(cors(CorsOptions(origin: 'https://example.com')))
          ..get('/data', (c) async {
            handlerRan = true;
            return c.json({'ok': true});
          });
        final client = TestClient(app);

        final response = await client.get(
          '/data',
          headers: {'origin': 'https://evil.example'},
        );

        expect(response.header('access-control-allow-origin'), isNull);
        expect(handlerRan, isTrue);
        expect(response.statusCode, equals(200));
        final json = await response.bodyAsJson();
        expect(json['ok'], isTrue);
      },
    );

    test('a list of allowed origins: a match gets allow-origin, a non-match gets none', () async {
      final app = Aim()
        ..use(
          cors(
            CorsOptions(
              origin: ['https://a.example.com', 'https://b.example.com'],
            ),
          ),
        )
        ..get('/data', (c) async => c.json({'ok': true}));
      final client = TestClient(app);

      final matched = await client.get(
        '/data',
        headers: {'origin': 'https://b.example.com'},
      );
      expect(
        matched.header('access-control-allow-origin'),
        equals('https://b.example.com'),
      );

      final unmatched = await client.get(
        '/data',
        headers: {'origin': 'https://c.example.com'},
      );
      expect(unmatched.header('access-control-allow-origin'), isNull);
    });

    test(
      'credentials adds allow-credentials for an allowed, specific origin',
      () async {
        final app = Aim()
          ..use(
            cors(CorsOptions(origin: 'https://example.com', credentials: true)),
          )
          ..get('/data', (c) async => c.json({'ok': true}));
        final client = TestClient(app);

        final response = await client.get(
          '/data',
          headers: {'origin': 'https://example.com'},
        );

        expect(
          response.header('access-control-allow-credentials'),
          equals('true'),
        );
      },
    );

    test('credentials is absent by default (no allow-credentials header on '
        'either a simple or a preflight response)', () async {
      final app = Aim()
        ..use(cors(CorsOptions(origin: 'https://example.com')))
        ..post('/data', (c) async => c.json({'ok': true}));
      final client = TestClient(app);

      final simple = await client.get(
        '/data',
        headers: {'origin': 'https://example.com'},
      );
      expect(simple.header('access-control-allow-credentials'), isNull);

      final preflight = await client.options(
        '/data',
        headers: {
          'origin': 'https://example.com',
          'access-control-request-method': 'POST',
        },
      );
      expect(preflight.header('access-control-allow-credentials'), isNull);
    });

    test('maxAge (seconds) is rendered as access-control-max-age on the preflight response', () async {
      final app = Aim()
        ..use(cors(CorsOptions(origin: 'https://example.com', maxAge: 3600)))
        ..post('/data', (c) async => c.json({'ok': true}));
      final client = TestClient(app);

      final response = await client.options(
        '/data',
        headers: {
          'origin': 'https://example.com',
          'access-control-request-method': 'POST',
        },
      );

      expect(response.header('access-control-max-age'), equals('3600'));
    });

    test('exposeHeaders adds access-control-expose-headers to a simple (non-preflight) response', () async {
      final app = Aim()
        ..use(
          cors(
            CorsOptions(
              origin: 'https://example.com',
              exposeHeaders: ['X-Request-Id', 'X-Response-Time'],
            ),
          ),
        )
        ..get('/data', (c) async => c.json({'ok': true}));
      final client = TestClient(app);

      final response = await client.get(
        '/data',
        headers: {'origin': 'https://example.com'},
      );

      expect(
        response.header('access-control-expose-headers'),
        equals('X-Request-Id, X-Response-Time'),
      );
    });
  });
}
