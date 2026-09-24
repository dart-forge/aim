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

final stringMinLengthSchema = Schema(
  (r) => (name: r.string('name', minLength: 3)),
);
final stringPatternSchema = Schema(
  (r) => (code: r.string('code', pattern: RegExp(r'^[a-z]+$'))),
);
final integerMaxSchema = Schema((r) => (age: r.integer('age', max: 10)));

final stringListOrNullSchema = Schema(
  (r) => (tags: r.stringListOrNull('tags', pattern: RegExp(r'^[a-z]+$'))),
);
final integerListOrNullSchema = Schema(
  (r) => (scores: r.integerListOrNull('scores')),
);
final numberListSchema = Schema((r) => (scores: r.numberList('scores')));
final numberListOrNullSchema = Schema(
  (r) => (scores: r.numberListOrNull('scores')),
);
final booleanListSchema = Schema((r) => (flags: r.booleanList('flags')));
final booleanListOrNullSchema = Schema(
  (r) => (flags: r.booleanListOrNull('flags')),
);
final dateTimeMinMaxSchema = Schema(
  (r) => (
    when: r.dateTime('when', min: DateTime.utc(2020), max: DateTime.utc(2030)),
  ),
);
final dateTimeListSchema = Schema(
  (r) => (
    whens: r.dateTimeList(
      'whens',
      min: DateTime.utc(2020),
      max: DateTime.utc(2030),
    ),
  ),
);
final dateTimeListOrNullSchema = Schema(
  (r) => (whens: r.dateTimeListOrNull('whens')),
);
final enumListSchema = Schema(
  (r) => (statuses: r.enumList('statuses', Status.values)),
);
final enumListOrNullSchema = Schema(
  (r) => (statuses: r.enumListOrNull('statuses', Status.values)),
);
final addressSchema = Schema((r) => (city: r.string('city')));
final objectListOrNullSchema = Schema(
  (r) => (jobs: r.objectListOrNull('jobs', addressSchema)),
);

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

  group('string constraints', () {
    test('enforces minLength', () {
      expect(
        () => stringMinLengthSchema.parse({'name': 'ab'}),
        throwsA(isA<ValidationException>()),
      );
      expect(stringMinLengthSchema.parse({'name': 'abc'}).name, 'abc');
    });

    test('enforces pattern', () {
      expect(
        () => stringPatternSchema.parse({'code': 'ABC'}),
        throwsA(isA<ValidationException>()),
      );
      expect(stringPatternSchema.parse({'code': 'abc'}).code, 'abc');
    });
  });

  group('integer constraints', () {
    test('enforces max', () {
      expect(
        () => integerMaxSchema.parse({'age': 11}),
        throwsA(isA<ValidationException>()),
      );
      expect(integerMaxSchema.parse({'age': 10}).age, 10);
    });

    test('accepts a double with nothing after the decimal point', () {
      expect(integerMaxSchema.parse({'age': 3.0}).age, 3);
    });

    test('still rejects a double with a fractional part', () {
      expect(
        () => integerMaxSchema.parse({'age': 3.7}),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('enumValue with no values', () {
    test('is refused with ArgumentError, not a bare "No element" crash', () {
      expect(
        () =>
            Schema((r) => (status: r.enumValue<Status>('status', const [])))
                .parse({'status': 'active'}),
        throwsArgumentError,
      );
    });
  });

  group('stringListOrNull', () {
    test('a missing field reads as null', () {
      expect(stringListOrNullSchema.parse({}).tags, isNull);
    });

    test('enforces pattern on each element', () {
      expect(
        () => stringListOrNullSchema.parse({
          'tags': ['abc', 'ABC'],
        }),
        throwsA(isA<ValidationException>()),
      );
      expect(
        stringListOrNullSchema.parse({
          'tags': ['abc', 'def'],
        }).tags,
        ['abc', 'def'],
      );
    });
  });

  group('integerListOrNull', () {
    test('a missing field reads as null', () {
      expect(integerListOrNullSchema.parse({}).scores, isNull);
    });

    test('reads a valid list', () {
      expect(
        integerListOrNullSchema.parse({
          'scores': [1, 2],
        }).scores,
        [1, 2],
      );
    });
  });

  group('numberList', () {
    test('reads a valid list', () {
      expect(
        numberListSchema.parse({
          'scores': [1.5, 2.5],
        }).scores,
        [1.5, 2.5],
      );
    });

    test('rejects an element of the wrong type', () {
      expect(
        () => numberListSchema.parse({
          'scores': [1.5, 'two'],
        }),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('numberListOrNull', () {
    test('a missing field reads as null', () {
      expect(numberListOrNullSchema.parse({}).scores, isNull);
    });
  });

  group('booleanList', () {
    test('reads a valid list', () {
      expect(
        booleanListSchema.parse({
          'flags': [true, false],
        }).flags,
        [true, false],
      );
    });

    test('rejects an element of the wrong type', () {
      expect(
        () => booleanListSchema.parse({
          'flags': [true, 'no'],
        }),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('booleanListOrNull', () {
    test('a missing field reads as null', () {
      expect(booleanListOrNullSchema.parse({}).flags, isNull);
    });
  });

  group('dateTime min/max', () {
    test('enforces min and max', () {
      expect(
        () => dateTimeMinMaxSchema.parse({'when': '2019-01-01T00:00:00Z'}),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => dateTimeMinMaxSchema.parse({'when': '2031-01-01T00:00:00Z'}),
        throwsA(isA<ValidationException>()),
      );
      expect(
        dateTimeMinMaxSchema.parse({'when': '2025-01-01T00:00:00Z'}).when,
        DateTime.parse('2025-01-01T00:00:00Z'),
      );
    });
  });

  group('dateTimeList', () {
    test('reads a valid list and enforces min/max per element', () {
      expect(
        dateTimeListSchema.parse({
          'whens': ['2025-01-01T00:00:00Z'],
        }).whens,
        [DateTime.parse('2025-01-01T00:00:00Z')],
      );
      expect(
        () => dateTimeListSchema.parse({
          'whens': ['2019-01-01T00:00:00Z'],
        }),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('dateTimeListOrNull', () {
    test('a missing field reads as null', () {
      expect(dateTimeListOrNullSchema.parse({}).whens, isNull);
    });
  });

  group('enumList', () {
    test('reads a valid list', () {
      expect(
        enumListSchema.parse({
          'statuses': ['active', 'inactive'],
        }).statuses,
        [Status.active, Status.inactive],
      );
    });

    test('rejects a value outside the enum', () {
      expect(
        () => enumListSchema.parse({
          'statuses': ['deleted'],
        }),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('enumListOrNull', () {
    test('a missing field reads as null', () {
      expect(enumListOrNullSchema.parse({}).statuses, isNull);
    });
  });

  group('objectListOrNull', () {
    test('a missing field reads as null', () {
      expect(objectListOrNullSchema.parse({}).jobs, isNull);
    });

    test('a populated field validates each element', () {
      expect(
        objectListOrNullSchema
            .parse({
              'jobs': [
                {'city': 'osaka'},
              ],
            })
            .jobs!
            .first
            .city,
        'osaka',
      );
    });
  });
}
