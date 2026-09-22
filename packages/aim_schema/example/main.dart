import 'package:aim_schema/aim_schema.dart';

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

void main() {
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

  // The same declaration describes itself, which is the material an
  // OpenAPI writer would build on.
  print(createUser.toJsonSchema());
}
