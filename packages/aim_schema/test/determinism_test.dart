import 'package:aim_schema/aim_schema.dart';
import 'package:test/test.dart';

void main() {
  test(
    'a procedure that branches on a value is refused, not silently wrong',
    () {
      // The recording pass has no values, so a schema like this would describe
      // one shape and validate another. Failing loudly is the whole point.
      final bad = Schema((r) {
        final kind = r.string('kind');
        return kind == 'a' ? (value: r.integer('a')) : (value: r.integer('b'));
      });

      // The recording pass sees 'kind' then 'b' (the dummy string is not 'a').
      expect(bad.toJsonSchema(), isNotNull);

      // A request whose kind really is 'a' reads 'a' second, which disagrees.
      expect(
        () => bad.parse({'kind': 'a', 'a': 1}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('kind'), contains('depends on')),
          ),
        ),
      );
    },
  );

  test('a procedure that reads the same fields every time is fine', () {
    final good = Schema((r) => (a: r.string('a'), b: r.integer('b')));
    expect(good.parse({'a': 'x', 'b': 1}).a, 'x');
    expect(good.parse({'a': 'y', 'b': 2}).b, 2);
  });
}
