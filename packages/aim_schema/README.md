# aim_schema

Validate request data and read it back with static types — no code
generation, no generated files.

[Documentation](https://aim-dart.dev/server/validation) | [pub.dev](https://pub.dev/packages/aim_schema)

## Not the other schema

Aim already uses the word "schema" for something else: `aim_orm`'s schema is
the shape of a database — the `aim.database.schema` setting and the tables
under `lib/schema/`. `aim_schema` is unrelated to that. It describes the
shape of a request (and, later, a response), not a table.

## Overview

`aim_schema` declares the shape of request data as a *procedure* that reads
it, rather than as a table of fields:

```dart
import 'package:aim_schema/aim_schema.dart';

final createUser = Schema((r) => (
      name: r.string('name', maxLength: 80),
      age: r.integer('age', min: 0),
      nickname: r.stringOrNull('nickname'),
    ));

void main() {
  final body = createUser.parse({'name': 'naoki', 'age': 34});

  // Statically typed, with no cast and no map subscript.
  final String name = body.name;
  final int age = body.age;
  final String? nickname = body.nickname;
}
```

The return type of the closure — a record literal — becomes the static type
of `Schema<R>`, so Dart infers `Schema<({int age, String name, String?
nickname})>` on its own. That inference is what a mapped type does in
TypeScript, and it is why this package generates nothing: no `build_runner`,
no generated files, and a fresh clone starts with a plain `dart pub get` and
`dart run`.

The same procedure is interpreted twice: once by a reader that hands back
placeholder values and records what was asked for (the material behind
`toJsonSchema()`), and once per request by a reader that validates real input
against that record.

`parse` collects every error it finds rather than stopping at the first, so a
caller can fix a request in one round trip.

## The procedure must be deterministic

Because the recording pass has no real input, the procedure cannot branch on
a value it has read:

```dart
// Don't do this — 'kind' is read, then used to decide what to read next.
Schema((r) {
  final kind = r.string('kind');
  return kind == 'a' ? (value: r.integer('a')) : (value: r.integer('b'));
});
```

The recording pass sees `'kind'` then `'b'` (a placeholder string is never
`'a'`), but a request whose `kind` really is `'a'` asks for `'a'` next. That
disagreement throws a `StateError` rather than silently describing one shape
and validating another. **A schema must read the same fields, in the same
order, every time it runs.**

For the same reason, a schema must not compute on a value right after reading
it — the recording pass hands out `''` for every string and `0` for every
number, so `DateTime.parse(r.string('date'))` or
`r.string('name').substring(0, 3)` fails while recording, with a message
explaining the rule rather than a bare `RangeError` or `FormatException`.
Move that kind of work to the caller, after `parse` returns.

## `OrNull` is a separate method

`required: false` can't turn `string`'s return type from `String` into
`String?` — a method's static return type doesn't change based on an
argument's value. `stringOrNull` (and the other `OrNull` methods) exist so an
optional field's Dart type reflects that at compile time.

## `coerce` is for text-only input

By default, `parse` is strict: a JSON body's `34` reads as an `int`, and its
`"34"` is a type error. Set `coerce: true` when the input is text throughout
— a query string, form fields, headers — so `"34"` reads as `34`. Coercion
is one-directional: it never turns a JSON number or boolean into a string,
so a JSON body's `{"name": 34}` is still a type error for a `string` field
even with `coerce: true`. The `Context.parseQuery` this package adds to
`aim_core`'s `Context` always coerces, since a query string has no types of
its own.

## What is not here yet

`toJsonSchema()` returns a JSON Schema description of a request schema. That
is the material an OpenAPI generator would be built from — this package does
not ship one. Response schemas and OpenAPI generation do not exist yet.

## Installation

```yaml
dependencies:
  aim_schema: ^0.4.0
```

## Documentation

For detailed usage, examples, and API reference, see the
[documentation](https://aim-dart.dev/server/validation).
