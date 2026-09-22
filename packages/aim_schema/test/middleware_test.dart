import 'package:aim_core/aim_core.dart';
import 'package:aim_schema/aim_schema.dart';
import 'package:aim_server_testing/aim_server_testing.dart';
import 'package:test/test.dart';

final createUser = Schema(
  (r) => (name: r.string('name', maxLength: 80), age: r.integer('age', min: 0)),
);

void main() {
  group('validationErrorsAsBadRequest', () {
    test(
      'turns a ValidationException into a 400 with every error listed',
      () async {
        final app = Aim()
          ..use(validationErrorsAsBadRequest())
          ..post('/users', (c) async {
            final body = await c.parse(createUser);
            return c.json({'name': body.name});
          });
        final client = TestClient(app);

        // 'name' is missing and 'age' fails its min bound: both errors
        // should come back, not just the first.
        final response = await client.post('/users', body: {'age': -1});

        expect(response.statusCode, equals(400));
        final json = await response.bodyAsJson();
        expect(json['error'], equals('Bad Request'));

        final details = (json['details'] as List).cast<Map<String, dynamic>>();
        expect(
          details.map((d) => d['path']),
          containsAll(<String>['name', 'age']),
        );
        // Not just "is a String" — '' passes that too. Check the actual
        // wording for each field.
        final byPath = {
          for (final detail in details) detail['path']: detail['message'],
        };
        expect(byPath['name'], 'is required');
        expect(byPath['age'], 'must be at least 0');
      },
    );

    test('a valid body still reaches the handler and its response', () async {
      final app = Aim()
        ..use(validationErrorsAsBadRequest())
        ..post('/users', (c) async {
          final body = await c.parse(createUser);
          return c.json({'name': body.name, 'age': body.age});
        });
      final client = TestClient(app);

      final response = await client.post(
        '/users',
        body: {'name': 'naoki', 'age': 34},
      );

      expect(response.statusCode, equals(200));
      final json = await response.bodyAsJson();
      expect(json['name'], equals('naoki'));
      expect(json['age'], equals(34));
    });

    test('an error other than ValidationException is not turned into a 400 '
        '— it is left for the application\'s own handler', () async {
      final app = Aim()
        ..use(validationErrorsAsBadRequest())
        ..get('/boom', (c) async {
          throw StateError('boom');
        });
      final client = TestClient(app);

      final response = await client.get('/boom');

      // No onError is registered, so this is Aim's own default 500 —
      // the middleware did not intercept it.
      expect(response.statusCode, equals(500));
    });

    test(
      "an application's own onError still runs for a non-validation error",
      () async {
        final app = Aim()
          ..use(validationErrorsAsBadRequest())
          ..onError(
            (error, c) async => c.json({'handled': '$error'}, statusCode: 502),
          )
          ..get('/boom', (c) async {
            throw StateError('boom');
          });
        final client = TestClient(app);

        final response = await client.get('/boom');

        expect(response.statusCode, equals(502));
        final json = await response.bodyAsJson();
        expect(json['handled'], contains('boom'));
      },
    );
  });
}
