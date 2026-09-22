import 'package:aim_schema/aim_schema.dart';
import 'package:test/test.dart';

final ageSchema = Schema((r) => (age: r.integer('age', min: 0)));
final activeSchema = Schema((r) => (active: r.boolean('active')));
final scoreSchema = Schema((r) => (score: r.number('score')));
final whenSchema = Schema((r) => (when: r.dateTime('when')));

void main() {
  group('coerce: false', () {
    test('a numeric string is not accepted for an integer field', () {
      expect(
        () => ageSchema.parse({'age': '34'}),
        throwsA(isA<ValidationException>()),
      );
    });

    test('a boolean-looking string is not accepted for a boolean field', () {
      expect(
        () => activeSchema.parse({'active': 'true'}),
        throwsA(isA<ValidationException>()),
      );
    });

    test('a numeric string is not accepted for a number field', () {
      expect(
        () => scoreSchema.parse({'score': '3.5'}),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('coerce: true', () {
    test('a numeric string is accepted for an integer field', () {
      expect(ageSchema.parse({'age': '34'}, coerce: true).age, 34);
    });

    test('a non-numeric string is still an error, not a silent default', () {
      // The whole point of coerce is converting a string that really does
      // represent an int, not falling back to a default when it does not.
      expect(
        () => ageSchema.parse({'age': 'abc'}, coerce: true),
        throwsA(isA<ValidationException>()),
      );
    });

    test('"true" and "1" are accepted for a boolean field', () {
      expect(activeSchema.parse({'active': 'true'}, coerce: true).active, true);
      expect(activeSchema.parse({'active': '1'}, coerce: true).active, true);
    });

    test('"false" and "0" are accepted for a boolean field', () {
      expect(
        activeSchema.parse({'active': 'false'}, coerce: true).active,
        false,
      );
      expect(activeSchema.parse({'active': '0'}, coerce: true).active, false);
    });

    test('a string that is neither true nor false is still an error', () {
      expect(
        () => activeSchema.parse({'active': 'nope'}, coerce: true),
        throwsA(isA<ValidationException>()),
      );
    });

    test('a numeric string is accepted for a number field', () {
      expect(scoreSchema.parse({'score': '3.5'}, coerce: true).score, 3.5);
    });

    test('a non-numeric string is still an error for a number field', () {
      expect(
        () => scoreSchema.parse({'score': 'abc'}, coerce: true),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('DateTime', () {
    test('an ISO 8601 string is accepted whether or not coerce is set', () {
      final parsed = DateTime.parse('2026-09-22T00:00:00Z');
      expect(whenSchema.parse({'when': '2026-09-22T00:00:00Z'}).when, parsed);
      expect(
        whenSchema.parse({'when': '2026-09-22T00:00:00Z'}, coerce: true).when,
        parsed,
      );
    });

    test('a string that is not a valid date-time is an error either way', () {
      expect(
        () => whenSchema.parse({'when': 'not a date'}),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => whenSchema.parse({'when': 'not a date'}, coerce: true),
        throwsA(isA<ValidationException>()),
      );
    });
  });
}
