---
title: Validation - Aim Framework
description: Validate request bodies and query strings in Dart with aim_schema. Declare a schema once, read it back with static types, no code generation.
head:
  - - meta
    - name: keywords
      content: Dart request validation, aim_schema, JSON Schema, type-safe validation, Aim validation middleware
---

# Validation

`aim_schema` validates request data and reads it back with static types —
without a cast, without a code generation step, and without a second,
hand-written type to keep in sync with the validation rules.

::: tip Not the other schema
`aim_orm` also uses the word "schema", for the shape of a database table
(the `aim.database.schema` setting, `lib/schema/`). This page is about
`aim_schema`, which describes the shape of a request or a response, not a
table.
:::

## Why

The usual way to validate a request body in Dart is to write a function that
checks a `Map<String, dynamic>`, throws or collects errors, and then hands
the caller... the same `Map<String, dynamic>`, cast field by field. The
validation rules and the type the rest of the code works with are two
separate things, written twice, that can drift apart.

`aim_schema` closes that gap by making the declaration the only source of
either one. You write a procedure that reads the fields you want, with the
constraints you want on each one:

```dart
import 'package:aim_schema/aim_schema.dart';

final createUser = Schema((r) => (
      name: r.string('name', maxLength: 80),
      age: r.integer('age', min: 0),
      nickname: r.stringOrNull('nickname'),
    ));
```

The closure's return type — here, a record literal — becomes the static
type argument of `Schema<R>`. Dart infers it from the closure body, so
`createUser` has type `Schema<({int age, String name, String? nickname})>`
with no annotation written anywhere. That inference is doing the same job a
mapped type does in TypeScript: turning one declaration into both a runtime
check and a static type. It's also why this package has nothing to generate
— there's no second, generated file for the inferred type to live in.

The same procedure — the same closure — is run twice, by two different
implementations of the `Reader` interface it's written against:

- A **recording** reader hands back a placeholder for every field
  (`''`, `0`, `false`, ...) and remembers what was asked for. Nothing here
  ever sees a real request; it's the material behind `toJsonSchema()`.
- A **validating** reader is created fresh for each request. It checks the
  real input against what the recording pass saw, reports every problem it
  finds, and returns the validated values.

## Declaring a schema

`Schema`'s constructor takes a function from a `Reader` to whatever record
(or other value) you want back. `Reader` has one method per scalar type,
each named for what it returns and each taking the field's name as its
first argument:

```dart
final createUser = Schema((r) => (
      name: r.string('name', maxLength: 80),
      age: r.integer('age', min: 0),
      active: r.boolean('active'),
      score: r.number('score', min: 0, max: 100),
      startedAt: r.dateTime('startedAt'),
    ));
```

| Method | Returns | Constraints |
|---|---|---|
| `r.string(name)` | `String` | `minLength`, `maxLength` |
| `r.integer(name)` | `int` | `min`, `max` |
| `r.number(name)` | `double` | `min`, `max` |
| `r.boolean(name)` | `bool` | — |
| `r.dateTime(name)` | `DateTime` | parsed from an ISO 8601 string |

### Optional fields

Every method above reads a *required* field: `parse` reports an error if
it's missing. For an optional field, use the `OrNull` counterpart —
`stringOrNull`, `integerOrNull`, `numberOrNull`, `booleanOrNull`,
`dateTimeOrNull` — which returns the nullable type instead:

```dart
final createUser = Schema((r) => (
      name: r.string('name'),
      nickname: r.stringOrNull('nickname'), // String?, not String
    ));
```

This is a separate method rather than a `required: false` argument on
`string` because an argument's *value* can't change a method's *static*
return type — Dart resolves `string`'s return type as `String` at compile
time no matter what you pass it. Giving optional fields their own method is
what lets `nickname` above come back as `String?` while `name` comes back as
`String`, both inferred, both without a cast.

### Enums

`r.enumValue(name, MyEnum.values)` reads a field that must match one of an
enum's constants, by `Enum.name`. Pass the enum's own `.values` — since that
list comes from the schema's declaration rather than from the request, using
it doesn't count as branching on the data being read (see
[The determinism rule](#the-determinism-rule)). `r.enumValueOrNull` is the
optional counterpart.

```dart
enum Role { admin, member }

final invite = Schema((r) => (
      email: r.string('email'),
      role: r.enumValue('role', Role.values),
    ));
```

## Reading it back

`Schema.parse` takes a `Map<String, Object?>` — typically a decoded JSON
body — and returns the record type, with every field already the right Dart
type:

```dart
final body = createUser.parse({'name': 'naoki', 'age': 34});
body.name; // String, no cast
body.age;  // int, no cast
```

If the input doesn't match, `parse` throws `ValidationException`, which
carries every problem found as a `List<ValidationError>` — not just the
first one, so a caller can fix a request in a single round trip:

```dart
try {
  createUser.parse({'age': 'not a number'});
} on ValidationException catch (e) {
  for (final error in e.errors) {
    print('${error.path}: ${error.message}');
    // name: is required
    // age: must be an integer
  }
}
```

## Nested and lists

A field can be another schema, read with `r.object` (or `r.objectOrNull`),
or a list of one, read with `r.objectList`:

```dart
final address = Schema((r) => (
      city: r.string('city'),
      zip: r.string('zip'),
    ));

final person = Schema((r) => (
      name: r.string('name'),
      address: r.object('address', address),
      tags: r.stringList('tags'),
      jobs: r.objectList('jobs', address),
    ));

final p = person.parse({
  'name': 'naoki',
  'address': {'city': 'tokyo', 'zip': '100'},
  'tags': ['a', 'b'],
  'jobs': [
    {'city': 'osaka', 'zip': '530'},
  ],
});

p.address.city;   // String, two levels deep
p.jobs.first.zip; // String, through objectList
```

A list of scalars uses `stringList` or `integerList` instead — a scalar
element has no field names of its own, so there's nothing to hand a nested
`Reader`, which is why those are separate methods from `objectList` rather
than one generic list method.

Errors inside a nested object or a list element are reported with a path
that shows where they are — `address.city`, `jobs[0].zip` — in the same flat
`errors` list as everything else, not nested inside a sub-exception.

## Query strings

A query string arrives as `Map<String, String>` — every value is text, even
`?age=34`. Reading it through the same `string`/`integer`/... methods with
`parse`'s default settings would reject `34` for not being an `int`. Pass
`coerce: true` to accept a scalar written as its own text representation:

```dart
final search = Schema((r) => (page: r.integer('page', min: 1)));

search.parse({'page': '3'}, coerce: true).page; // 3, an int
```

`coerce` only affects how a *scalar* is read — `'true'`/`'1'` for a
`boolean`, a numeric string for `integer` or `number`. A value that isn't a
valid representation of its type is still an error either way; `coerce`
doesn't fall back to a default. A `DateTime` field parses the same string
whether or not `coerce` is set, since a date is written as a string in JSON
too.

Inside `aim_server`, `Context.parseQuery` reads `c.query` through a schema
with `coerce` already on, since a query string is text by nature:

```dart
app.get('/items', (c) async {
  final query = c.parseQuery(search);
  return c.json({'page': query.page});
});
```

## Errors and 400

`Context.parse` reads and validates the JSON body:

```dart
app.post('/users', (c) async {
  final body = await c.parse(createUser); // throws ValidationException
  return c.json({'name': body.name});
});
```

On its own, a thrown `ValidationException` reaches the app's error handling
exactly like any other unhandled error — a 500, or whatever `Aim.onError`
does. Add the `validationErrorsAsBadRequest()` middleware to turn it into a
400 instead, with the full error list as the body:

```dart
final app = Aim()
  ..use(validationErrorsAsBadRequest())
  ..post('/users', (c) async {
    final body = await c.parse(createUser);
    return c.json({'name': body.name}, statusCode: 201);
  });
```

A rejected request gets:

```json
{
  "error": "Bad Request",
  "details": [
    {"path": "name", "message": "is required"},
    {"path": "age", "message": "must be at least 0"}
  ]
}
```

Any error that isn't a `ValidationException` passes through untouched, so
this middleware can sit alongside your own error handling without changing
how anything else fails.

## The determinism rule

A schema's procedure must ask for the same fields, in the same order, every
time it runs — because the recording pass has no real values to make a
decision with. Branching on what was read looks like it would work (Dart
doesn't stop you writing it), but it fails loudly the first time a real
request disagrees with what the recorder saw:

```dart
// Don't do this.
Schema((r) {
  final kind = r.string('kind');
  return kind == 'a' ? (value: r.integer('a')) : (value: r.integer('b'));
});
```

While recording, `kind` reads as `''` (the placeholder), so the branch takes
the `'b'` side and the recorded shape is `{kind, b}`. A real request whose
`kind` really is `'a'` then asks for `'a'` — which doesn't match what was
recorded — and `parse` throws a `StateError` describing exactly that: which
field it expected, which one it got, and which field was read right before
the mismatch.

The same restriction rules out computing on a value right after reading it.
The recording pass hands out `''` for every string and `0` for every
number, so this fails too, for the same underlying reason:

```dart
// Don't do this either.
Schema((r) => (code: r.string('name').substring(0, 3)));
```

`''.substring(0, 3)` throws a `RangeError` during recording — before
`aim_schema` gets a chance to explain anything — so this case is caught
separately and re-thrown as a `StateError` that names the rule instead of
just the symptom: a schema may only read fields and hand back the raw
values; do `DateTime.parse`, substring work, arithmetic, and the like on the
result of `parse`, in your own code, not inside the schema.

## What is not here yet

`toJsonSchema()` returns a JSON Schema description of the request shape a
`Schema` declares — the same information the validating reader checks
against, written out as a `Map<String, Object?>`:

```dart
print(createUser.toJsonSchema());
// {type: object, properties: {name: {type: string, maxLength: 80}, ...},
//  required: [name, age]}
```

That's the material an OpenAPI document or a response schema would be built
from. Neither exists yet: there is no response-schema counterpart to
`Schema`, and nothing in this package turns a `toJsonSchema()` output (or a
whole app's routes) into an OpenAPI document.
