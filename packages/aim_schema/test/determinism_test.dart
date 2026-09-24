import 'package:aim_schema/aim_schema.dart';
import 'package:test/test.dart';

enum _Kind { a, b }

// A schema that reads a list of itself. Only a top-level (or field) `late
// final` can reference itself in its own initializer this way — a local
// variable inside a test body cannot. Dart has no equirecursive types, so
// `kids` needs an explicit `dynamic` rather than the type Schema would
// otherwise infer for it.
final Schema<({String name, List<dynamic> kids})> tree = Schema(
  (r) => (name: r.string('name'), kids: r.objectList('kids', tree)),
);

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

      // The recording pass sees 'kind' then 'b' (the dummy string is not
      // 'a') — check the recorded shape itself, not just that some value
      // came back.
      expect(bad.toJsonSchema()['required'], ['kind', 'b']);

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

  test('a procedure that computes on a value it reads fails with a message '
      'about the rule, not a bare error from the placeholder value', () {
    // Different from the branching case above: this procedure reads the
    // same field every time, it just does substring work on it. During
    // the recording pass that value is '' (the placeholder), so
    // ''.substring(0, 3) throws a RangeError with no idea this package
    // even exists.
    final bad = Schema((r) => (code: r.string('name').substring(0, 3)));

    expect(
      () => bad.toJsonSchema(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('computes on a value'), contains('placeholder')),
        ),
      ),
    );
  });

  test('the same computed-on-a-read-value failure is reported by parse, since '
      'it also records first', () {
    final bad = Schema((r) => (code: r.string('name').substring(0, 3)));

    expect(() => bad.parse({'name': 'naoki'}), throwsA(isA<StateError>()));
  });

  test('a procedure that swaps a plain string for a dateTime under the same '
      'field name is caught, even though both share the JSON Schema type '
      '"string"', () {
    // While recording, kind reads as '' (never 'a'), so the dateTime
    // branch is taken and 'x' is recorded as a dateTime, not a plain
    // string. Before the determinism check compared `format`, this
    // passed silently: [type] alone is 'string' either way.
    final bad = Schema((r) {
      final kind = r.string('kind');
      return kind == 'a' ? (value: r.string('x')) : (value: r.dateTime('x'));
    });

    expect(
      () => bad.parse({'kind': 'a', 'x': 'hello'}),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('depends on'),
        ),
      ),
    );
  });

  test('a procedure that swaps a plain string for an enumValue under the same '
      'field name is caught, for the same reason', () {
    final bad = Schema((r) {
      final kind = r.string('kind');
      return kind == 'a'
          ? (value: r.string('x'))
          : (value: r.enumValue('x', _Kind.values));
    });

    expect(
      () => bad.parse({'kind': 'a', 'x': 'hello'}),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('depends on'),
        ),
      ),
    );
  });

  test('a schema that references itself is refused with one clear message, '
      'not a StackOverflowError behind a wall of repeated text', () {
    // Recording 'tree' asks (through objectList) for tree's own spec
    // again, before the first recording has finished — there is no base
    // case. This is the first thing anyone reaching for a tree-shaped
    // payload tries.
    expect(
      () => tree.toJsonSchema(),
      throwsA(
        isA<StateError>()
            .having((e) => e.message, 'message', contains('references itself'))
            // The bug this guards against is the message growing by one
            // copy of "computes on a value"/"references itself" per
            // level of recursion. One occurrence is expected; two would
            // mean the catch-all in Schema.spec re-wrapped its own error.
            .having(
              (e) => e.message.split('references itself').length - 1,
              'occurrences of "references itself"',
              1,
            ),
      ),
    );
  });
}
