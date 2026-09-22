import 'package:aim_schema/aim_schema.dart';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_testing/aim_server_testing.dart';

// A schema is a procedure that reads request data, not a table of fields.
// Its static type is inferred from what the procedure returns, so this is
// `Schema<({int age, String name, String? nickname})>` with no annotation
// and nothing generated.
final createUser = Schema(
  (r) => (
    name: r.string('name', maxLength: 80),
    age: r.integer('age', min: 0),
    nickname: r.stringOrNull('nickname'),
  ),
);

Future<void> main() async {
  // Parse a plain map directly. No aim_server involved yet — a schema
  // works the same way wherever the map comes from.
  final body = createUser.parse({'name': 'naoki', 'age': 34});

  // Statically typed: no cast, no map subscript.
  print('name: ${body.name}, age: ${body.age}, nickname: ${body.nickname}');

  try {
    createUser.parse({'name': 'x' * 100, 'age': 'not a number'});
  } on ValidationException catch (e) {
    // Every problem is reported at once, not just the first.
    for (final error in e.errors) {
      print('invalid: $error');
    }
  }

  // The same declaration describes itself. That description is the
  // material an OpenAPI writer would be built from — this package does not
  // ship one.
  print(createUser.toJsonSchema());

  // Now the same schema, read from an actual request through c.parse.
  // validationErrorsAsBadRequest turns a rejected body into a 400 with the
  // full error list; without it, ValidationException would reach the
  // app's own error handler like any other error.
  final app = Aim()
    ..use(validationErrorsAsBadRequest())
    ..post('/users', (c) async {
      final body = await c.parse(createUser);
      return c.json({'name': body.name, 'age': body.age}, statusCode: 201);
    });

  // TestClient drives the app in-process — no socket, so this example
  // starts and finishes on its own instead of sitting on a listening port.
  final client = TestClient(app);

  final created = await client.post(
    '/users',
    body: {'name': 'naoki', 'age': 34},
  );
  print(
    'POST /users (valid): ${created.statusCode} ${await created.bodyAsJson()}',
  );

  final rejected = await client.post('/users', body: {'age': -1});
  print(
    'POST /users (invalid): ${rejected.statusCode} '
    '${await rejected.bodyAsJson()}',
  );
}
