import 'package:aim_schema/aim_schema.dart';
import 'package:test/test.dart';

enum Status { active, inactive }

final numberSchema = Schema((r) => (score: r.number('score', min: 0, max: 10)));
final numberOrNullSchema = Schema((r) => (score: r.numberOrNull('score')));
final booleanSchema = Schema((r) => (active: r.boolean('active')));
final booleanOrNullSchema = Schema((r) => (active: r.booleanOrNull('active')));
final dateTimeSchema = Schema((r) => (when: r.dateTime('when')));
final dateTimeOrNullSchema = Schema((r) => (when: r.dateTimeOrNull('when')));
final integerOrNullSchema = Schema((r) => (age: r.integerOrNull('age')));
final enumSchema = Schema(
  (r) => (status: r.enumValue('status', Status.values)),
);
final enumOrNullSchema = Schema(
  (r) => (status: r.enumValueOrNull('status', Status.values)),
);
final stringListSchema = Schema(
  (r) => (tags: r.stringList('tags', minItems: 1, maxItems: 3)),
);
final integerListSchema = Schema((r) => (scores: r.integerList('scores')));

void main() {
  group('number', () {
    test('reads a valid number', () {
      expect(numberSchema.parse({'score': 4.5}).score, 4.5);
    });

    test('rejects the wrong type', () {
      expect(
        () => numberSchema.parse({'score': 'nope'}),
        throwsA(isA<ValidationException>()),
      );
    });

    test('enforces min and max', () {
      expect(
        () => numberSchema.parse({'score': 11}),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('numberOrNull', () {
    test('a missing field reads as null', () {
      expect(numberOrNullSchema.parse({}).score, isNull);
    });

    test('rejects the wrong type', () {
      expect(
        () => numberOrNullSchema.parse({'score': 'nope'}),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('boolean', () {
    test('reads a valid boolean', () {
      expect(booleanSchema.parse({'active': true}).active, true);
    });

    test('rejects the wrong type', () {
      expect(
        () => booleanSchema.parse({'active': 'yes'}),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('booleanOrNull', () {
    test('a missing field reads as null', () {
      expect(booleanOrNullSchema.parse({}).active, isNull);
    });

    test('rejects the wrong type', () {
      expect(
        () => booleanOrNullSchema.parse({'active': 1}),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('dateTime', () {
    test('reads a valid ISO 8601 string', () {
      final body = dateTimeSchema.parse({'when': '2026-01-01T00:00:00Z'});
      expect(body.when, DateTime.parse('2026-01-01T00:00:00Z'));
    });

    test('rejects the wrong type', () {
      expect(
        () => dateTimeSchema.parse({'when': 1234}),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects a string that is not a valid date-time', () {
      expect(
        () => dateTimeSchema.parse({'when': 'not a date'}),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('dateTimeOrNull', () {
    test('a missing field reads as null', () {
      expect(dateTimeOrNullSchema.parse({}).when, isNull);
    });

    test('rejects a string that is not a valid date-time', () {
      expect(
        () => dateTimeOrNullSchema.parse({'when': 'not a date'}),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('integerOrNull', () {
    test('a missing field reads as null', () {
      expect(integerOrNullSchema.parse({}).age, isNull);
    });

    test('rejects the wrong type', () {
      expect(
        () => integerOrNullSchema.parse({'age': 'nope'}),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('enumValue', () {
    test('reads a valid value', () {
      expect(enumSchema.parse({'status': 'active'}).status, Status.active);
    });

    test('rejects a value outside the enum', () {
      expect(
        () => enumSchema.parse({'status': 'deleted'}),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects the wrong type', () {
      expect(
        () => enumSchema.parse({'status': 1}),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('enumValueOrNull', () {
    test('a missing field reads as null', () {
      expect(enumOrNullSchema.parse({}).status, isNull);
    });

    test('rejects a value outside the enum', () {
      expect(
        () => enumOrNullSchema.parse({'status': 'deleted'}),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('stringList', () {
    test('reads a valid list', () {
      expect(
        stringListSchema.parse({
          'tags': ['a', 'b'],
        }).tags,
        ['a', 'b'],
      );
    });

    test('rejects the wrong type', () {
      expect(
        () => stringListSchema.parse({'tags': 'not a list'}),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects an element of the wrong type', () {
      expect(
        () => stringListSchema.parse({
          'tags': ['a', 1],
        }),
        throwsA(isA<ValidationException>()),
      );
    });

    test('enforces minItems and maxItems', () {
      expect(
        () => stringListSchema.parse({'tags': <String>[]}),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => stringListSchema.parse({
          'tags': ['a', 'b', 'c', 'd'],
        }),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('integerList', () {
    test('reads a valid list', () {
      expect(
        integerListSchema.parse({
          'scores': [1, 2, 3],
        }).scores,
        [1, 2, 3],
      );
    });

    test('rejects the wrong type', () {
      expect(
        () => integerListSchema.parse({'scores': 'not a list'}),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects an element of the wrong type', () {
      expect(
        () => integerListSchema.parse({
          'scores': [1, 'two'],
        }),
        throwsA(isA<ValidationException>()),
      );
    });
  });
}
