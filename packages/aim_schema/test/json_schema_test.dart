import 'package:aim_schema/aim_schema.dart';
import 'package:test/test.dart';

enum Role { admin, member }

// A single schema exercising every branch of FieldSpec.toJsonSchema: a
// nested object (with its own nested `required`), an array of objects, an
// array of a scalar with an item-level format, and an enum. Before this
// test, the object and array branches of that method were checked by hand
// during review but never asserted by a test — about half the method's
// logic had no automatic coverage at all.
final address = Schema(
  (r) => (city: r.string('city'), zip: r.stringOrNull('zip')),
);

final invite = Schema(
  (r) => (
    email: r.string('email', maxLength: 80),
    role: r.enumValue('role', Role.values),
    tags: r.stringList('tags', minItems: 1, maxItems: 5),
    reachableAt: r.dateTimeList('reachableAt', min: DateTime.utc(2020)),
    address: r.object('address', address),
    previousAddresses: r.objectList('previousAddresses', address, maxItems: 3),
  ),
);

void main() {
  test('describes a nested object, an array of objects, and scalar arrays '
      'with an item-level format, all in one pass', () {
    expect(invite.toJsonSchema(), {
      'type': 'object',
      'properties': {
        'email': {'type': 'string', 'maxLength': 80},
        'role': {
          'type': 'string',
          'enum': ['admin', 'member'],
        },
        'tags': {
          'type': 'array',
          'minItems': 1,
          'maxItems': 5,
          'items': {'type': 'string'},
        },
        'reachableAt': {
          'type': 'array',
          'items': {
            'type': 'string',
            'format': 'date-time',
            'formatMinimum': '2020-01-01T00:00:00.000Z',
          },
        },
        'address': {
          'type': 'object',
          'properties': {
            'city': {'type': 'string'},
            'zip': {'type': 'string'},
          },
          'required': ['city'],
        },
        'previousAddresses': {
          'type': 'array',
          'maxItems': 3,
          'items': {
            'type': 'object',
            'properties': {
              'city': {'type': 'string'},
              'zip': {'type': 'string'},
            },
            'required': ['city'],
          },
        },
      },
      'required': [
        'email',
        'role',
        'tags',
        'reachableAt',
        'address',
        'previousAddresses',
      ],
    });
  });

  test('a string pattern is described as the RegExp\'s own pattern text', () {
    final schema = Schema(
      (r) => (code: r.string('code', pattern: RegExp(r'^[a-z]+$'))),
    );

    expect(schema.toJsonSchema(), {
      'type': 'object',
      'properties': {
        'code': {'type': 'string', 'pattern': '^[a-z]+\$'},
      },
      'required': ['code'],
    });
  });

  test('an optional field is described without appearing in required', () {
    final schema = Schema(
      (r) => (name: r.string('name'), nickname: r.stringOrNull('nickname')),
    );

    expect(schema.toJsonSchema(), {
      'type': 'object',
      'properties': {
        'name': {'type': 'string'},
        'nickname': {'type': 'string'},
      },
      'required': ['name'],
    });
  });
}
