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
}
