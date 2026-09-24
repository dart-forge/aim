import 'package:aim_schema/aim_schema.dart';
import 'package:test/test.dart';

enum Role { admin, member }

typedef Team = ({String name});
typedef User = ({
  int id,
  String name,
  String? nick,
  DateTime at,
  Role role,
  Team team,
  List<Team> teams,
  List<int> scores,
});

final teamOut = Output<Team>(
  (w) => [w.string('name', (t) => t.name, minLength: 1)],
);
final userOut = Output<User>(
  (w) => [
    w.integer('id', (u) => u.id, min: 1),
    w.string('name', (u) => u.name, pattern: RegExp(r'^\w+$')),
    w.stringOrNull('nick', (u) => u.nick),
    w.dateTime('at', (u) => u.at),
    w.enumValue('role', (u) => u.role, Role.values),
    w.object('team', (u) => u.team, teamOut),
    w.objectList('teams', (u) => u.teams, teamOut),
    w.integerList('scores', (u) => u.scores, maxItems: 2),
  ],
);

User ok() => (
  id: 1,
  name: 'naoki',
  nick: null,
  at: DateTime.utc(2026, 9, 24),
  role: Role.admin,
  team: (name: 'a'),
  teams: [(name: 'b')],
  scores: [1],
);

void main() {
  test('encodes a valid value to JSON-ready values', () {
    expect(userOut.encode(ok()), {
      'id': 1,
      'name': 'naoki',
      'nick': null,
      'at': '2026-09-24T00:00:00.000Z',
      'role': 'admin',
      'team': {'name': 'a'},
      'teams': [
        {'name': 'b'},
      ],
      'scores': [1],
    });
  });

  test('collects every violation with its path', () {
    final bad = (
      id: 0,
      name: 'a b',
      nick: null,
      at: DateTime.utc(2026),
      role: Role.admin,
      team: (name: ''),
      teams: [(name: 'x'), (name: '')],
      scores: [1, 2, 3],
    );
    try {
      userOut.encode(bad);
      fail('expected ResponseValidationException');
    } on ResponseValidationException catch (e) {
      expect(e.errors.map((x) => x.path), [
        'id',
        'name',
        'team.name',
        'teams[1].name',
        'scores',
      ]);
    }
  });

  test('toString carries no paths or values', () {
    final e = ResponseValidationException([
      const ValidationError('secret', 'must be at least 1'),
    ]);
    expect(e.toString(), isNot(contains('secret')));
  });

  test('NaN is rejected', () {
    final out = Output<double>((w) => [w.number('n', (v) => v)]);
    expect(
      () => out.encode(double.nan),
      throwsA(isA<ResponseValidationException>()),
    );
  });

  test(
    "spec is available without a value and matches Schema's JSON Schema shape",
    () {
      final schema = Schema(
        (r) => (id: r.integer('id', min: 1), nick: r.stringOrNull('nick')),
      );
      final out = Output<({int id, String? nick})>(
        (w) => [
          w.integer('id', (v) => v.id, min: 1),
          w.stringOrNull('nick', (v) => v.nick),
        ],
      );
      expect(out.toJsonSchema(), schema.toJsonSchema());
    },
  );

  test('toJsonSchema matches Schema for a list, an enum, a nested object, an '
      'object list, and a dateTime with min/max', () {
    final min = DateTime.utc(2020);
    final max = DateTime.utc(2030);
    final teamSchema = Schema((r) => (name: r.string('name', minLength: 1)));
    final schema = Schema(
      (r) => (
        tags: r.stringList('tags', minItems: 1),
        role: r.enumValue('role', Role.values),
        team: r.object('team', teamSchema),
        teams: r.objectList('teams', teamSchema),
        at: r.dateTime('at', min: min, max: max),
      ),
    );
    final out =
        Output<
          ({
            List<String> tags,
            Role role,
            Team team,
            List<Team> teams,
            DateTime at,
          })
        >(
          (w) => [
            w.stringList('tags', (v) => v.tags, minItems: 1),
            w.enumValue('role', (v) => v.role, Role.values),
            w.object('team', (v) => v.team, teamOut),
            w.objectList('teams', (v) => v.teams, teamOut),
            w.dateTime('at', (v) => v.at, min: min, max: max),
          ],
        );
    expect(out.toJsonSchema(), schema.toJsonSchema());
  });

  test('duplicate field names are rejected', () {
    expect(
      () => Output<int>(
        (w) => [w.integer('a', (v) => v), w.integer('a', (v) => v)],
      ),
      throwsArgumentError,
    );
  });

  // --- one test per remaining form ---

  test('stringOrNull writes null and encodes constraints', () {
    final out = Output<String?>(
      (w) => [w.stringOrNull('s', (v) => v, minLength: 2)],
    );
    expect(out.encode(null), {'s': null});
    expect(out.encode('ab'), {'s': 'ab'});
    expect(() => out.encode('a'), throwsA(isA<ResponseValidationException>()));
  });

  test('stringList encodes and enforces minItems', () {
    final out = Output<List<String>>(
      (w) => [w.stringList('s', (v) => v, minItems: 1)],
    );
    expect(out.encode(['a', 'b']), {
      's': ['a', 'b'],
    });
    try {
      out.encode([]);
      fail('expected error');
    } on ResponseValidationException catch (e) {
      expect(e.errors.single.path, 's');
    }
  });

  test('stringListOrNull writes null when absent', () {
    final out = Output<List<String>?>(
      (w) => [w.stringListOrNull('s', (v) => v)],
    );
    expect(out.encode(null), {'s': null});
    expect(out.encode(['a']), {
      's': ['a'],
    });
  });

  test('integerOrNull writes null and enforces bounds', () {
    final out = Output<int?>((w) => [w.integerOrNull('n', (v) => v, min: 0)]);
    expect(out.encode(null), {'n': null});
    expect(() => out.encode(-1), throwsA(isA<ResponseValidationException>()));
  });

  test('integerListOrNull writes null and enforces maxItems', () {
    final out = Output<List<int>?>(
      (w) => [w.integerListOrNull('n', (v) => v, maxItems: 1)],
    );
    expect(out.encode(null), {'n': null});
    try {
      out.encode([1, 2]);
      fail('expected error');
    } on ResponseValidationException catch (e) {
      expect(e.errors.single.path, 'n');
    }
  });

  test('numberOrNull writes null and rejects NaN', () {
    final out = Output<double?>((w) => [w.numberOrNull('n', (v) => v)]);
    expect(out.encode(null), {'n': null});
    expect(
      () => out.encode(double.nan),
      throwsA(isA<ResponseValidationException>()),
    );
  });

  test('numberList encodes and rejects a NaN element', () {
    final out = Output<List<double>>((w) => [w.numberList('n', (v) => v)]);
    expect(out.encode([1.5, 2.5]), {
      'n': [1.5, 2.5],
    });
    try {
      out.encode([double.nan]);
      fail('expected error');
    } on ResponseValidationException catch (e) {
      expect(e.errors.single.path, 'n[0]');
    }
  });

  test('numberListOrNull writes null when absent', () {
    final out = Output<List<double>?>(
      (w) => [w.numberListOrNull('n', (v) => v)],
    );
    expect(out.encode(null), {'n': null});
    expect(out.encode([1.0]), {
      'n': [1.0],
    });
  });

  test('boolean encodes', () {
    final out = Output<bool>((w) => [w.boolean('b', (v) => v)]);
    expect(out.encode(true), {'b': true});
  });

  test('booleanOrNull writes null when absent', () {
    final out = Output<bool?>((w) => [w.booleanOrNull('b', (v) => v)]);
    expect(out.encode(null), {'b': null});
    expect(out.encode(false), {'b': false});
  });

  test('booleanList encodes', () {
    final out = Output<List<bool>>((w) => [w.booleanList('b', (v) => v)]);
    expect(out.encode([true, false]), {
      'b': [true, false],
    });
  });

  test('booleanListOrNull writes null when absent', () {
    final out = Output<List<bool>?>(
      (w) => [w.booleanListOrNull('b', (v) => v)],
    );
    expect(out.encode(null), {'b': null});
  });

  test('dateTimeOrNull writes null and enforces bounds', () {
    final min = DateTime.utc(2020);
    final out = Output<DateTime?>(
      (w) => [w.dateTimeOrNull('d', (v) => v, min: min)],
    );
    expect(out.encode(null), {'d': null});
    expect(
      () => out.encode(DateTime.utc(2010)),
      throwsA(isA<ResponseValidationException>()),
    );
  });

  test('dateTimeList encodes and enforces per-element bounds', () {
    final min = DateTime.utc(2020);
    final out = Output<List<DateTime>>(
      (w) => [w.dateTimeList('d', (v) => v, min: min)],
    );
    expect(out.encode([DateTime.utc(2021)]), {
      'd': ['2021-01-01T00:00:00.000Z'],
    });
    try {
      out.encode([DateTime.utc(2010)]);
      fail('expected error');
    } on ResponseValidationException catch (e) {
      expect(e.errors.single.path, 'd[0]');
    }
  });

  test('dateTimeListOrNull writes null when absent', () {
    final out = Output<List<DateTime>?>(
      (w) => [w.dateTimeListOrNull('d', (v) => v)],
    );
    expect(out.encode(null), {'d': null});
  });

  test('enumValueOrNull writes null and rejects an out-of-range value', () {
    final out = Output<Role?>(
      (w) => [
        w.enumValueOrNull('r', (v) => v, [Role.admin]),
      ],
    );
    expect(out.encode(null), {'r': null});
    try {
      out.encode(Role.member);
      fail('expected error');
    } on ResponseValidationException catch (e) {
      expect(e.errors.single.message, 'must be one of admin');
    }
  });

  test('enumList encodes and rejects an out-of-range element', () {
    final out = Output<List<Role>>(
      (w) => [
        w.enumList('r', (v) => v, [Role.admin]),
      ],
    );
    expect(out.encode([Role.admin]), {
      'r': ['admin'],
    });
    try {
      out.encode([Role.member]);
      fail('expected error');
    } on ResponseValidationException catch (e) {
      expect(e.errors.single.path, 'r[0]');
    }
  });

  test('enumListOrNull writes null when absent', () {
    final out = Output<List<Role>?>(
      (w) => [w.enumListOrNull('r', (v) => v, Role.values)],
    );
    expect(out.encode(null), {'r': null});
  });

  test('objectOrNull writes null when absent and validates when present', () {
    final out = Output<Team?>(
      (w) => [w.objectOrNull('team', (v) => v, teamOut)],
    );
    expect(out.encode(null), {'team': null});
    try {
      out.encode((name: ''));
      fail('expected error');
    } on ResponseValidationException catch (e) {
      expect(e.errors.single.path, 'team.name');
    }
  });

  test('objectListOrNull writes null when absent', () {
    final out = Output<List<Team>?>(
      (w) => [w.objectListOrNull('teams', (v) => v, teamOut)],
    );
    expect(out.encode(null), {'teams': null});
    expect(out.encode([(name: 'a')]), {
      'teams': [
        {'name': 'a'},
      ],
    });
  });

  // --- additional coverage: fix round 1 ---

  test('integerList encodes', () {
    final out = Output<List<int>>((w) => [w.integerList('n', (v) => v)]);
    expect(out.encode([1, 2, 3]), {
      'n': [1, 2, 3],
    });
  });

  test('string minLength and maxLength violations are reported', () {
    final out = Output<String>(
      (w) => [w.string('s', (v) => v, minLength: 2, maxLength: 4)],
    );
    try {
      out.encode('a');
      fail('expected error');
    } on ResponseValidationException catch (e) {
      expect(e.errors.single.message, 'must be at least 2 characters');
    }
    try {
      out.encode('abcde');
      fail('expected error');
    } on ResponseValidationException catch (e) {
      expect(e.errors.single.message, 'must be at most 4 characters');
    }
  });

  test('objectList minItems and maxItems violations are reported', () {
    final out = Output<List<Team>>(
      (w) => [
        w.objectList('teams', (v) => v, teamOut, minItems: 1, maxItems: 2),
      ],
    );
    try {
      out.encode([]);
      fail('expected error');
    } on ResponseValidationException catch (e) {
      expect(e.errors.single, isA<ValidationError>());
      expect(e.errors.single.path, 'teams');
      expect(e.errors.single.message, 'must have at least 1 item(s)');
    }
    try {
      out.encode([(name: 'a'), (name: 'b'), (name: 'c')]);
      fail('expected error');
    } on ResponseValidationException catch (e) {
      expect(e.errors.single.path, 'teams');
      expect(e.errors.single.message, 'must have at most 2 item(s)');
    }
  });

  test('number Infinity is rejected', () {
    final out = Output<double>((w) => [w.number('n', (v) => v)]);
    expect(
      () => out.encode(double.infinity),
      throwsA(isA<ResponseValidationException>()),
    );
    expect(
      () => out.encode(double.negativeInfinity),
      throwsA(isA<ResponseValidationException>()),
    );
  });
}
