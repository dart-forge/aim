import 'package:aim_schema/aim_schema.dart';
import 'package:test/test.dart';

final withDuplicateRead = Schema(
  (r) => (first: r.string('name'), second: r.string('name')),
);

void main() {
  group('Schema.spec', () {
    test('is unmodifiable, so a caller cannot corrupt every future parse', () {
      final schema = Schema((r) => (name: r.string('name')));

      expect(() => schema.spec.clear(), throwsUnsupportedError);
      // The schema still works after the attempt above threw — nothing was
      // actually mutated.
      expect(schema.parse({'name': 'naoki'}).name, 'naoki');
    });

    test('a nested schema\'s spec is unmodifiable too', () {
      final address = Schema((r) => (city: r.string('city')));
      final person = Schema((r) => (address: r.object('address', address)));

      final nested = person.spec.first.nested!;
      expect(() => nested.clear(), throwsUnsupportedError);
    });
  });

  group('Schema.toJsonSchema with a field read twice', () {
    test('required lists each field name once, even if it was read twice', () {
      expect(withDuplicateRead.toJsonSchema()['required'], ['name']);
    });
  });

  group('ValidationException.errors', () {
    test('is unmodifiable', () {
      final schema = Schema((r) => (name: r.string('name')));

      try {
        schema.parse({});
        fail('expected a ValidationException');
      } on ValidationException catch (e) {
        expect(
          () => e.errors.add(const ValidationError('x', 'y')),
          throwsUnsupportedError,
        );
      }
    });
  });

  group('Schema.readWith', () {
    test('runs the declaration directly against a custom Reader', () {
      final schema = Schema(
        (r) => (name: r.string('name'), age: r.integer('age')),
      );

      // Not Schema.parse and not the library's own Recorder/Validator — a
      // minimal third-party Reader that always returns the same fixed
      // values, to prove readWith is a usable extension point on its own.
      final result = schema.readWith(_FixedReader());

      expect(result.name, 'fixed');
      expect(result.age, 7);
    });
  });
}

/// A bare-bones [Reader] that answers every scalar read with a fixed value,
/// ignoring the field name and every constraint. Enough to prove
/// [Schema.readWith] works with something other than this library's own
/// Recorder/Validator, without reimplementing either.
class _FixedReader implements Reader {
  @override
  String string(
    String name, {
    int? minLength,
    int? maxLength,
    Pattern? pattern,
  }) => 'fixed';

  @override
  int integer(String name, {int? min, int? max}) => 7;

  @override
  double number(String name, {double? min, double? max}) => 7;

  @override
  bool boolean(String name) => true;

  @override
  DateTime dateTime(String name, {DateTime? min, DateTime? max}) =>
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  @override
  String? stringOrNull(
    String name, {
    int? minLength,
    int? maxLength,
    Pattern? pattern,
  }) => 'fixed';

  @override
  int? integerOrNull(String name, {int? min, int? max}) => 7;

  @override
  double? numberOrNull(String name, {double? min, double? max}) => 7;

  @override
  bool? booleanOrNull(String name) => true;

  @override
  DateTime? dateTimeOrNull(String name, {DateTime? min, DateTime? max}) =>
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  @override
  T enumValue<T extends Enum>(String name, List<T> values) => values.first;

  @override
  T? enumValueOrNull<T extends Enum>(String name, List<T> values) =>
      values.first;

  @override
  List<String> stringList(
    String name, {
    int? minItems,
    int? maxItems,
    Pattern? pattern,
  }) => const [];

  @override
  List<String>? stringListOrNull(
    String name, {
    int? minItems,
    int? maxItems,
    Pattern? pattern,
  }) => const [];

  @override
  List<int> integerList(String name, {int? minItems, int? maxItems}) =>
      const [];

  @override
  List<int>? integerListOrNull(String name, {int? minItems, int? maxItems}) =>
      const [];

  @override
  List<double> numberList(String name, {int? minItems, int? maxItems}) =>
      const [];

  @override
  List<double>? numberListOrNull(String name, {int? minItems, int? maxItems}) =>
      const [];

  @override
  List<bool> booleanList(String name, {int? minItems, int? maxItems}) =>
      const [];

  @override
  List<bool>? booleanListOrNull(String name, {int? minItems, int? maxItems}) =>
      const [];

  @override
  List<DateTime> dateTimeList(
    String name, {
    int? minItems,
    int? maxItems,
    DateTime? min,
    DateTime? max,
  }) => const [];

  @override
  List<DateTime>? dateTimeListOrNull(
    String name, {
    int? minItems,
    int? maxItems,
    DateTime? min,
    DateTime? max,
  }) => const [];

  @override
  List<T> enumList<T extends Enum>(
    String name,
    List<T> values, {
    int? minItems,
    int? maxItems,
  }) => const [];

  @override
  List<T>? enumListOrNull<T extends Enum>(
    String name,
    List<T> values, {
    int? minItems,
    int? maxItems,
  }) => const [];

  @override
  List<A> objectList<A>(
    String name,
    Schema<A> itemSchema, {
    int? minItems,
    int? maxItems,
  }) => const [];

  @override
  List<A>? objectListOrNull<A>(
    String name,
    Schema<A> itemSchema, {
    int? minItems,
    int? maxItems,
  }) => const [];

  @override
  A object<A>(String name, Schema<A> schema) => schema.readWith(this);

  @override
  A? objectOrNull<A>(String name, Schema<A> schema) => null;
}
