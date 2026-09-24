import 'package:aim_schema/aim_schema.dart';
import 'package:test/test.dart';

final idOut = Output<({int id})>((w) => [w.integer('id', (v) => v.id, min: 1)]);
final msgOut = Output<String>((w) => [w.string('message', (v) => v)]);

void main() {
  test('collects entries in order and keeps the record typed', () {
    final res = responses(
      (r) => (
        created: r(201, idOut),
        conflict: r(409, msgOut, description: 'taken'),
      ),
    );
    expect(res.all.map((e) => e.status), [201, 409]);
    expect(res.all[1].description, 'taken');
    final reply = res.entries.created((id: 7));
    expect(reply.status, 201);
    expect(reply.body, {'id': 7});
  });

  test('calling an entry with a violating value throws', () {
    final res = responses((r) => (created: r(201, idOut)));
    expect(
      () => res.entries.created((id: 0)),
      throwsA(isA<ResponseValidationException>()),
    );
  });

  test('duplicate status is rejected', () {
    expect(
      () => responses((r) => (a: r(200, idOut), b: r(200, msgOut))),
      throwsArgumentError,
    );
  });

  test('status outside 100-599 is rejected', () {
    expect(() => responses((r) => (a: r(600, idOut))), throwsArgumentError);
    expect(() => responses((r) => (a: r(99, idOut))), throwsArgumentError);
  });

  test('a builder used after responses returned is rejected', () {
    late ResponseBuilder leaked;
    responses((r) {
      leaked = r;
      return (a: r(200, idOut));
    });
    expect(() => leaked(201, idOut), throwsStateError);
  });

  test('an entry has its output and status readable', () {
    final res = responses((r) => (a: r(201, idOut)));
    expect(res.all.single.output, same(idOut));
    expect(res.all.single.status, 201);
    expect(res.all.single.description, isNull);
  });
}
