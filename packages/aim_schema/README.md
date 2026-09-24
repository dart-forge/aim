# aim_schema

Validate requests and declare responses with static types, without code
generation.

[Documentation](https://aim-dart.dev/server/validation) | [pub.dev](https://pub.dev/packages/aim_schema)

## Not the other schema

Aim already uses the word "schema" for something else: `aim_orm`'s schema is
the shape of a database — the `aim.database.schema` setting and the tables
under `lib/schema/`. `aim_schema` is unrelated to that. It describes the
shape of a request and a response, not a table.

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

## Declaring a response

`Output` is the write-side counterpart of `Schema`: instead of reading
fields out of a `Map`, it reads them off an already-typed value through a
getter, and encodes them to JSON — checking the same kind of constraints
along the way. `responses` collects a route's possible responses as named
entries, and `typed` binds request schemas and those responses to one
handler:

```dart
final userOut = Output<({int id, String name})>((w) => [
      w.integer('id', (u) => u.id, min: 1),
      w.string('name', (u) => u.name, minLength: 1),
    ]);

final userResponses = responses((r) => (ok: r(200, userOut)));

app.get('/users/:id', typed(
  path: Schema((r) => (id: r.integer('id'))),
  responses: userResponses,
  (c, req, res) async => res.ok((id: req.path.id, name: 'naoki')),
));
```

A handler must return a `Reply`, which rules out `c.json(...)` or an
ad-hoc map at compile time — it has to call one of the entries in `res`.
Using `res` naturally keeps a handler to its own route's entries, but
`Reply` itself isn't tied to a route, so calling an entry from a different
route's `responses` and returning that instead would compile too. A value
that doesn't match its entry's declared `Output` throws
`ResponseValidationException` — the same kind of error, with every
violation collected, that `Schema.parse` throws for a request.

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

`toJsonSchema()` returns a JSON Schema description of a request or response
schema — the material an OpenAPI generator would be built from. `typed`
records a route's schemas and responses (`routeContractOf`) so a generator
could read them, but this package does not ship one; nothing here turns a
route's contract into an OpenAPI document yet.

## Installation

Not published to pub.dev yet, so there is no `dart pub add aim_schema` or
version constraint to add today. Once it is, its only runtime dependency is
`aim_core`.

## Documentation

For detailed usage, examples, and API reference, see the
[documentation](https://aim-dart.dev/server/validation).
