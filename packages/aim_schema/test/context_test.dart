import 'package:aim_core/aim_core.dart';
import 'package:aim_schema/aim_schema.dart';
import 'package:aim_server_testing/aim_server_testing.dart';
import 'package:test/test.dart';

final createUser = Schema(
  (r) => (name: r.string('name', maxLength: 80), age: r.integer('age', min: 0)),
);

void main() {
  group('SchemaContext.parse', () {
    test('reads the JSON body and returns it with static types', () async {
      final app = Aim()
        ..post('/users', (c) async {
          final body = await c.parse(createUser);
          // The point of the whole design: no cast, no map subscript.
          final String name = body.name;
          final int age = body.age;
          return c.json({'name': name, 'age': age});
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

    test('a ValidationException from a bad body reaches the framework like '
        'any other unhandled error, unless validationErrorsAsBadRequest is '
        'installed (see middleware_test.dart)', () async {
      final app = Aim()
        ..post('/users', (c) async {
          await c.parse(createUser);
          return c.text('unreachable');
        });
      final client = TestClient(app);

      final response = await client.post('/users', body: {'age': -1});

      expect(response.statusCode, equals(500));
    });
  });

  group('SchemaContext.parseQuery', () {
    test('coerces the text query string to typed values', () async {
      final search = Schema((r) => (page: r.integer('page', min: 1)));
      final app = Aim()
        ..get('/items', (c) async {
          final query = c.parseQuery(search);
          final int page = query.page;
          return c.json({'page': page});
        });
      final client = TestClient(app);

      // A query string is text throughout, so `page=3` arrives as '3'.
      final response = await client.get('/items', query: {'page': '3'});

      expect(response.statusCode, equals(200));
      final json = await response.bodyAsJson();
      expect(json['page'], equals(3));
    });

    test('a query value that fails to coerce is still an error', () async {
      final search = Schema((r) => (page: r.integer('page', min: 1)));
      final app = Aim()
        ..get('/items', (c) async {
          final query = c.parseQuery(search);
          return c.json({'page': query.page});
        });
      final client = TestClient(app);

      final response = await client.get('/items', query: {'page': 'nope'});

      expect(response.statusCode, equals(500));
    });
  });
}
