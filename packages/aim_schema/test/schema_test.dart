import 'package:aim_schema/aim_schema.dart';
import 'package:test/test.dart';

final createUser = Schema(
  (r) => (
    name: r.string('name', maxLength: 80),
    age: r.integer('age', min: 0),
    nickname: r.stringOrNull('nickname'),
  ),
);

void main() {
  test('reads the fields back with static types', () {
    final body = createUser.parse({'name': 'naoki', 'age': 34});

    // The point of the whole design: these are statically typed, with no cast
    // and no map subscript in the caller.
    final String name = body.name;
    final int age = body.age;
    final String? nickname = body.nickname;

    expect(name, 'naoki');
    expect(age, 34);
    expect(nickname, isNull);
  });

  test('collects every error rather than stopping at the first', () {
    expect(
      () => createUser.parse({'name': 'x' * 100, 'age': 'nope'}),
      throwsA(
        isA<ValidationException>().having(
          (e) => e.errors.map((v) => v.path).toList(),
          'paths',
          ['name', 'age'],
        ),
      ),
    );
  });

  test('a missing required field is an error, not a null', () {
    expect(
      () => createUser.parse({'age': 1}),
      throwsA(isA<ValidationException>()),
    );
  });

  test('writes a schema from the same declaration', () {
    expect(createUser.toJsonSchema(), {
      'type': 'object',
      'properties': {
        'name': {'type': 'string', 'maxLength': 80},
        'age': {'type': 'integer', 'minimum': 0},
        'nickname': {'type': 'string'},
      },
      'required': ['name', 'age'],
    });
  });
}
