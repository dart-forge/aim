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

::: warning Not yet published to pub.dev
`aim_schema` lives in the [`dart-forge/aim`](https://github.com/dart-forge/aim)
monorepo but is not published to pub.dev, so there is no `dart pub add
aim_schema` command or `^x.y.z` version to depend on yet. Everything below
describes the package as it exists in the repository today.
:::

## Installation

Not published to pub.dev yet (see the warning above). Once it is, installing
it will add `aim_core` as its only runtime dependency.

::: tip Not the other schema
`aim_orm` also uses the word "schema", for the shape of a database table
(the `aim.database.schema` setting, `lib/schema/`). This page is about
`aim_schema`, which describes the shape of a request and a response, not a
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

A `number` field rejects `NaN`, `Infinity` and `-Infinity`. Dart's number
parser accepts all three spellings, and a query string is always coerced, so
without this `?price=NaN` would reach a handler — and `NaN` is the one value
`min` and `max` cannot stop, since every comparison with it is false.

An `integer` field also accepts a JSON number with nothing after the decimal
point — `3.0`, not `3.7` — regardless of `coerce`. Some JSON encoders (a
Python client, Dart's own `double` literals) write a whole number this way,
and rejecting it would be a 400 the caller has no way to act on: the value
really is the integer the schema asked for.

Every scalar type here also has a list form (`stringList`, `integerList`,
...) and a nullable form of each (`stringOrNull`, `stringListOrNull`, ...) —
see [Nested and lists](#nested-and-lists) below and the `Reader` API
reference for the complete set.

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

An `OrNull` field cannot tell "the key was absent" apart from "the key was
present with an explicit `null`" — both read as `null`. A required field
reports a missing key as `"is required"`, not as a type error, so that case
is distinguishable, but there's no way to ask `aim_schema` to require the
*key* while still accepting `null` as its value. This matters for a PATCH
endpoint, where the two are normally different instructions —
`{"nickname": null}` means "clear it", an absent `nickname` means "leave it
alone" — so a schema alone can't express that distinction; a PATCH handler
needs to inspect the raw body for which keys were sent, separately from
validating the values that were.

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

## Responses

`aim_schema` also has a write side: `Output` declares the shape of a
response body, the same way `Schema` declares the shape of a request.
Where a `Schema`'s `Reader` reads fields out of an untyped `Map`, an
`Output`'s `Writer` reads them off an already-typed value through a getter
you supply, encodes them to JSON-ready values, and checks the same kind of
constraints — `minLength`, `min`/`max`, `pattern`, `minItems`/`maxItems` —
against what came out:

```dart
final userOut = Output<({int id, String name})>((w) => [
      w.integer('id', (u) => u.id, min: 1),
      w.string('name', (u) => u.name, minLength: 1, maxLength: 80),
    ]);
```

Every `Reader` method has a `Writer` counterpart with the same name and the
same constraint parameters — `string`/`stringOrNull`/`stringList`/
`stringListOrNull`, `integer`, `number`, `boolean`, `dateTime`, `enumValue`,
`object`, and their list and nullable forms. `encode` runs a value through
them and returns a `Map<String, Object?>` ready for `Context.json`, or
throws `ResponseValidationException` — carrying every violation found, the
same as `ValidationException` does for requests — if the value doesn't
match:

```dart
final json = userOut.encode((id: 1, name: 'naoki'));
// {'id': 1, 'name': 'naoki'}

userOut.encode((id: 0, name: '')); // throws ResponseValidationException
```

Request and response declarations are separate types on purpose. A
`Schema`'s `Reader` reads fields out of an untyped `Map` by name and hands
back a typed value; an `Output`'s `Writer` does the opposite — it starts
from an already-typed value and reads its fields by calling a getter,
because Dart has no way to look up a record's field by a name given at
runtime. `Schema` and `Output` share the same `FieldSpec` shape underneath
— `toJsonSchema()` on either produces the same kind of description — but
one can't stand in for the other.

### Declaring a route's responses

A route rarely returns just one shape — success, not found, a validation
problem — each possibly with its own body. `responses` collects them as a
record of named entries, each declared with a status code and an `Output`:

```dart
final userResponses = responses((r) => (
      ok: r(200, userOut),
      notFound: r(
        404,
        Output<String>((w) => [w.string('message', (m) => m)]),
        description: 'no such user',
      ),
    ));
```

`build` runs once, eagerly, the same as `Schema`'s recording pass. Two
entries can't share a status code, and a status outside 100–599 is
rejected — both as `ArgumentError` — and the `ResponseBuilder` it received
stops working once `responses` has returned, so it can't be captured and
called again later.

Calling an entry with a value encodes it through its `Output` and wraps the
result in a `Reply`:

```dart
final reply = userResponses.entries.ok((id: 7, name: 'naoki'));
reply.status; // 200
reply.body;   // {'id': 7, 'name': 'naoki'}
```

`Reply` is opaque — the only way to make one is to call an entry — so a
handler can only ever return a response from its own route's `responses`,
not an arbitrary value.

### Binding it to a route with `typed`

`typed` reads a route's request data through up to three `Schema`s —
`path`, `query`, `body`, each optional — and hands the result, plus the
responses' typed entries, to a handler that must return a `Reply`:

```dart
final userPath = Schema((r) => (id: r.integer('id')));

app.get('/users/:id', typed(
  path: userPath,
  responses: userResponses,
  (c, req, res) async {
    final user = await findUser(req.path.id);
    if (user == null) return res.notFound('no such user');
    return res.ok((id: user.id, name: user.name));
  },
));
```

`req.body`, `req.query`, and `req.path` are typed from the `Schema`s passed
to `typed` — a location left out reads as `null`, typed `Object?`. Reading
fails exactly the way calling `Context.parse`/`parseQuery` directly would:
any of the three throws `ValidationException` before the handler runs, so
`validationErrorsAsBadRequest()` turns a bad request into a 400 the same
way it already does for an untyped route. `typed` then calls the handler,
encodes the `Reply` it returns, and sends it with `Context.json` at the
status its entry declared.

If the handler builds a value that doesn't match its declared `Output` — a
bug in the handler, not in the request — the `ResponseEntry` call throws
`ResponseValidationException` while encoding, before anything is sent.
Left unhandled, that becomes whatever `Aim.onError` does with an uncaught
error — a 500 by default — and, because `ResponseValidationException`'s
`toString()` reports only how many violations there were, not their paths
or values, a default 500 handler that puts `$e` straight into the response
body doesn't leak which fields or values were wrong. Reading
`ResponseValidationException.errors` — the same `List<ValidationError>`
shape `ValidationException` carries — is how a custom `onError` would
report or log the actual violations server-side.

`typed` also records what it was given, for anything that wants to read a
route's contract back rather than reproduce it — for example, a future
generator that walks an app's routes and turns each one's `Schema`s and
`Output`s (both already produce `toJsonSchema()`) into an OpenAPI document.
`routeContractOf` looks it up by the handler function `typed` returned:

```dart
final handler = typed(
  path: userPath,
  responses: userResponses,
  (c, req, res) async => res.ok((id: 1, name: 'a')),
);

final contract = routeContractOf(handler)!;
contract.path;      // userPath
contract.body;      // null — not declared
contract.responses; // [ResponseEntry(200, ...), ResponseEntry(404, ...)]
```

Nothing in `aim_schema` turns that contract into OpenAPI yet — it's
recorded so that kind of tooling can be built on top of it later.

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

`coerce` is one-directional: it only lets a scalar's own text representation
stand in for it — `'true'`/`'1'`/`'0'`/`'false'` for a `boolean`, a numeric
string for `integer` or `number`. It never goes the other way. A JSON body's
`{"name": 34}` is a type error for a `string` field whether or not `coerce`
is set — a number is never turned into a string, so one schema can be
shared between a JSON body and a coerced query string without a wrongly
typed body silently becoming text. A value that isn't a valid representation
of its type is still an error either way; `coerce` doesn't fall back to a
default. A `DateTime` field parses the same string whether or not `coerce`
is set, since a date is written as a string in JSON too.

`Context.parseQuery` — added to `aim_core`'s `Context` by this package, so
it works the same on every one of Aim's runtimes, not just `aim_server` —
reads `c.query` through a schema with `coerce` already on, since a query
string is text by nature:

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

A body that is not valid JSON, or is valid JSON but not an object (an array,
a string, `null`), is the client's mistake like any failed field, so it gets
the same 400. No single field is at fault, so the path is empty, and the two
cases say different things so the client can tell which mistake it made:

```json
{"error": "Bad Request",
 "details": [{"path": "", "message": "the request body is not valid JSON"}]}
```

```json
{"error": "Bad Request",
 "details": [{"path": "", "message": "the request body must be a JSON object"}]}
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

## Describing a schema

`toJsonSchema()` returns a JSON Schema description of the request shape a
`Schema` declares — the same information the validating reader checks
against, written out as a `Map<String, Object?>`:

```dart
print(createUser.toJsonSchema());
// {type: object, properties: {name: {type: string, maxLength: 80}, ...},
//  required: [name, age]}
```

This works today, for any schema — nested objects, lists, enums, and every
constraint a `Reader` method accepts all come through, and it's covered by
tests. It's the material an OpenAPI document would be built from. See
[Responses](#responses) above for `Output`, the response-schema
counterpart to `Schema`, which produces the same shape of `toJsonSchema()`
output. Nothing in this package turns either one (or a whole app's routes)
into an OpenAPI document yet; `typed`'s `routeContractOf` records what a
route declares so that kind of tooling can be built against it later.
