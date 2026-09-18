---
title: Code Generation - Aim ORM
description: Setup and understand the generated code for aim_orm.
head:
  - - meta
    - name: keywords
      content: Dart ORM codegen, build_runner, code generation
---

# Code Generation

aim_orm uses `build_runner` to generate type-safe query builders from your schema definitions.

## Setup

### 1. Add Dependencies

```yaml
# pubspec.yaml
dependencies:
  aim_orm: ^0.0.1
  aim_orm_postgres: ^0.0.1
  aim_postgres: ^0.0.1

dev_dependencies:
  build_runner: ^2.4.0
  aim_orm_codegen: ^0.0.1
```

### 2. Configure Schema Path

Specify your schema file location in `pubspec.yaml`:

```yaml
# pubspec.yaml
aim:
  database:
    schema: lib/schema.dart
```

This tells the code generator and migration tools where to find your table definitions.

::: tip
If not specified, the default path is `lib/schema`, which may be a file or a directory.
:::

### 3. Define Schema

Create a file with your table definitions:

```dart
// lib/tables.dart
import 'package:aim_orm/aim_orm.dart';
import 'package:aim_orm_postgres/aim_orm_postgres.dart';
import 'package:aim_postgres/aim_postgres.dart';

part 'tables.g.dart';

@PgTable('users')
final users = (
  id: uuid('id').primaryKey(),
  name: varchar('name', length: 255),
  email: varchar('email', length: 255).unique(),
  createdAt: timestamp('created_at').withDefaultNow(),
);

@PgTable('posts')
final posts = (
  id: serial('id').primaryKey(),
  userId: uuid('user_id'),
  title: varchar('title', length: 255),
  content: text('content'),
  createdAt: timestamp('created_at').withDefaultNow(),
);
```

### 4. Run Code Generation

```bash
# One-time build
dart run build_runner build

# Watch mode (regenerate on file changes)
dart run build_runner watch
```

## Generated Code

For each `@PgTable` definition, the following is generated:

### Database Extension

```dart
extension PostgresUsersDatabaseX on PostgresDatabase {
  UsersQueryBuilder get users => UsersQueryBuilder(this);
}
```

This allows you to access tables directly from the database connection:

```dart
final db = await PostgresDatabase.connect('...');
db.users  // UsersQueryBuilder
db.posts  // PostsQueryBuilder
```

### Row Type

```dart
typedef UsersRow = ({
  String id,
  String name,
  String email,
  DateTime createdAt,
});
```

### Query Builder

```dart
class UsersQueryBuilder {
  UsersSelectBuilder select();
  UsersInsertBuilder insert();
  UsersUpdateBuilder update();
  UsersDeleteBuilder delete();
}
```

## File Structure

```
lib/
├── tables.dart      # Your schema definitions
├── tables.g.dart    # Generated code (do not edit)
└── main.dart        # Your application code
```

## Regenerating Code

Run the build command after modifying schema:

```bash
dart run build_runner build --delete-conflicting-outputs
```

## Troubleshooting

### "Could not find a file named tables.g.dart"

Make sure you have:
1. Added `part 'tables.g.dart';` to your schema file
2. Run `dart run build_runner build`

### Build Errors

```bash
# Clean and rebuild
dart run build_runner clean
dart run build_runner build
```

## Next Steps

- [Schema Definition](/database/orm/schema) - Define tables and columns
- [SELECT](/database/orm/select) - Query data
- [INSERT](/database/orm/insert) - Insert data
- [Transactions](/database/orm/transactions) - Atomic operations