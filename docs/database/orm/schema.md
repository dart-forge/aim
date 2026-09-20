---
title: Schema Definition - Aim ORM
description: Define database schemas using Dart 3 Records. Column types, modifiers, and table definitions.
head:
  - - meta
    - name: keywords
      content: Dart ORM schema, table definition, column types, database schema
---

# Schema Definition

Define tables using Dart 3 Record syntax with the `@PgTable` annotation.

::: tip Schema File Location
Configure your schema file path in `pubspec.yaml`:
```yaml
aim:
  database:
    schema: lib/schema.dart  # default
```
See [Code Generation](/database/orm/codegen) for full setup.
:::

## Table Definition

```dart
import 'package:aim_orm/aim_orm.dart';
import 'package:aim_orm_postgres/aim_orm_postgres.dart';
import 'package:aim_postgres/aim_postgres.dart';

part 'tables.g.dart';

@PgTable('users')
final users = (
  id: uuid('id').primaryKey(),
  name: varchar('name', length: 255),
  email: varchar('email', length: 255).unique(),
  createdAt: timestamp('created_at').withDefault(DateTime.now()),
);
```

Key points:
- Use `@PgTable('table_name')` to specify the database table name
- Define columns as Record fields
- Add `part 'filename.g.dart'` for code generation

## Column Types

### Basic Types (aim_orm)

| Function | SQL Type | Dart Type |
|----------|----------|-----------|
| `integer(name)` | INTEGER | `int` |
| `varchar(name, length:)` | VARCHAR(n) | `String` |
| `text(name)` | TEXT | `String` |
| `timestamp(name)` | TIMESTAMP | `DateTime` |

`DateTime` values read back are always UTC (`isUtc == true`); call
`.toLocal()` for display.

### PostgreSQL Types (aim_orm_postgres)

| Function | PostgreSQL Type | Dart Type |
|----------|-----------------|-----------|
| `serial(name)` | SERIAL | `int` |
| `uuid(name)` | UUID | `String` |
| `jsonb<T>(name)` | JSONB | `T` |

## Column Modifiers

Chain modifiers to add constraints:

```dart
// Primary key
id: uuid('id').primaryKey(),

// Unique constraint
email: varchar('email', length: 255).unique(),

// Nullable
bio: text('bio').nullable(),

// Default value
createdAt: timestamp('created_at').withDefault(DateTime.now()),

// Timestamp with NOW() default
updatedAt: timestamp('updated_at').withDefaultNow(),
```

### Available Modifiers

| Modifier | Description |
|----------|-------------|
| `.primaryKey()` | Set as primary key |
| `.unique()` | Add unique constraint |
| `.nullable()` | Allow NULL values |
| `.withDefault(value)` | Set default value (not on `serial()`: the sequence already provides one) |
| `.withDefaultNow()` | Set default to NOW() (timestamp only) |

## Multiple Tables

Define multiple tables in the same file:

```dart
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

@PgTable('comments')
final comments = (
  id: serial('id').primaryKey(),
  postId: integer('post_id'),
  userId: uuid('user_id'),
  body: text('body'),
  createdAt: timestamp('created_at').withDefaultNow(),
);
```

## Column Name Mapping

The first argument to column functions is the database column name:

```dart
@PgTable('users')
final users = (
  // Dart field: createdAt
  // Database column: created_at
  createdAt: timestamp('created_at'),

  // Dart field: userId
  // Database column: user_id
  userId: uuid('user_id'),
);
```

## Generated Types

After running `dart run build_runner build`, each table gets a Row type:

```dart
// Generated from users table
typedef UsersRow = ({
  String id,
  String name,
  String email,
  DateTime createdAt,
});

// Generated from posts table
typedef PostsRow = ({
  int id,
  String userId,
  String title,
  String content,
  DateTime createdAt,
});
```

## Next Steps

- [SELECT](/database/orm/select) - Query data
- [INSERT](/database/orm/insert) - Insert data
- [Transactions](/database/orm/transactions) - Atomic operations
- [Code Generation](/database/orm/codegen) - Generated code details