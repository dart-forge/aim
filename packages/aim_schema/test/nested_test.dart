import 'package:aim_schema/aim_schema.dart';
import 'package:test/test.dart';

final address = Schema((r) => (city: r.string('city'), zip: r.string('zip')));
final company = Schema(
  (r) => (name: r.string('name'), address: r.object('address', address)),
);
final person = Schema(
  (r) => (
    name: r.string('name'),
    company: r.object('company', company),
    tags: r.stringList('tags'),
    jobs: r.objectList('jobs', address),
  ),
);

final withOptionalAddress = Schema(
  (r) => (name: r.string('name'), address: r.objectOrNull('address', address)),
);

final withOptionalAddressAndTrailingField = Schema(
  (r) => (address: r.objectOrNull('address', address), tag: r.string('tag')),
);

final withRequiredAddressAndTrailingField = Schema(
  (r) => (address: r.object('address', address), tag: r.string('tag')),
);

final withJobsAndTrailingField = Schema(
  (r) => (jobs: r.objectList('jobs', address), tag: r.string('tag')),
);

final withBoundedJobs = Schema(
  (r) => (jobs: r.objectList('jobs', address, minItems: 1, maxItems: 2)),
);

void main() {
  test('nested records keep their types two levels down', () {
    final p = person.parse({
      'name': 'naoki',
      'company': {
        'name': 'dena',
        'address': {'city': 'tokyo', 'zip': '100'},
      },
      'tags': ['a', 'b'],
      'jobs': [
        {'city': 'osaka', 'zip': '530'},
      ],
    });

    final String city = p.company.address.city;
    final List<String> tags = p.tags;
    final String jobCity = p.jobs.first.city;

    expect(city, 'tokyo');
    expect(tags, ['a', 'b']);
    expect(jobCity, 'osaka');
  });

  test('an error inside a nested object carries the path', () {
    expect(
      () => person.parse({
        'name': 'n',
        'company': {
          'name': 'd',
          'address': {'city': 1, 'zip': '1'},
        },
        'tags': <String>[],
        'jobs': <Object>[],
      }),
      throwsA(
        isA<ValidationException>().having(
          (e) => e.errors.first.path,
          'path',
          'company.address.city',
        ),
      ),
    );
  });

  test('an error inside a list carries the index', () {
    expect(
      () => person.parse({
        'name': 'n',
        'company': {
          'name': 'd',
          'address': {'city': 'c', 'zip': 'z'},
        },
        'tags': <String>[],
        'jobs': [
          {'city': 1, 'zip': 'z'},
        ],
      }),
      throwsA(
        isA<ValidationException>().having(
          (e) => e.errors.first.path,
          'path',
          'jobs[0].city',
        ),
      ),
    );
  });

  group('objectOrNull', () {
    test('a missing field reads as null', () {
      final result = withOptionalAddress.parse({'name': 'naoki'});
      expect(result.address, isNull);
    });

    test('a populated field validates and returns it', () {
      final result = withOptionalAddress.parse({
        'name': 'naoki',
        'address': {'city': 'tokyo', 'zip': '100'},
      });
      expect(result.address!.city, 'tokyo');
    });

    test('the wrong type is an error, and the field after it still runs', () {
      expect(
        () => withOptionalAddressAndTrailingField.parse({
          'address': 'not an object',
          'tag': 1,
        }),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors.map((v) => v.path).toList(),
            'paths',
            ['address', 'tag'],
          ),
        ),
      );
    });
  });

  group('object with a non-Map value', () {
    test('is an error, and the procedure keeps running rather than stopping '
        'at the bad field', () {
      expect(
        () => withRequiredAddressAndTrailingField.parse({
          'address': 'not an object',
          'tag': 1,
        }),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors.map((v) => v.path).toList(),
            'paths',
            ['address', 'tag'],
          ),
        ),
      );
    });
  });

  group('objectList with a non-Map element', () {
    test('is an error for that element, and the procedure keeps running '
        'rather than stopping at the bad element', () {
      expect(
        () => withJobsAndTrailingField.parse({
          'jobs': ['not an object'],
          'tag': 1,
        }),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors.map((v) => v.path).toList(),
            'paths',
            ['jobs[0]', 'tag'],
          ),
        ),
      );
    });
  });

  group('objectList minItems/maxItems', () {
    test('enforces both', () {
      expect(
        () => withBoundedJobs.parse({'jobs': <Object>[]}),
        throwsA(isA<ValidationException>()),
      );
      final threeJobs = [
        {'city': 'a', 'zip': '1'},
        {'city': 'b', 'zip': '2'},
        {'city': 'c', 'zip': '3'},
      ];
      expect(
        () => withBoundedJobs.parse({'jobs': threeJobs}),
        throwsA(isA<ValidationException>()),
      );
      final oneJob = [threeJobs.first];
      expect(withBoundedJobs.parse({'jobs': oneJob}).jobs.length, 1);
    });
  });
}
