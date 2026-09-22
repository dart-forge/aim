# aim_schema

Validate request data and read it back with static types — no code
generation, no generated files.

[Documentation](https://aim-dart.dev/schema) | [pub.dev](https://pub.dev/packages/aim_schema)

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
TypeScript, and it is why nothing here needs to be generated.

The same procedure is interpreted twice: once by a reader that returns dummy
values and records what was asked for (the material behind `toJsonSchema()`),
and once per request by a reader that validates real input against that
record. A schema that would ask for different fields depending on the data it
reads is refused rather than silently describing one shape and validating
another — see the tests for the exact failure.

`parse` collects every error it finds rather than stopping at the first, so a
caller can fix a request in one round trip.

## Installation

```yaml
dependencies:
  aim_schema: ^0.4.0
```

## Documentation

For detailed usage, examples, and API reference, see the
[documentation](https://aim-dart.dev/schema).
