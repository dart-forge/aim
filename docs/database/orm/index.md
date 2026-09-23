---
title: ORM Overview - Aim Database
description: Type-safe ORM for Dart with code generation. Define schemas using Dart 3 Records and get type-safe query builders.
head:
  - - meta
    - name: keywords
      content: Dart ORM, aim_orm, type-safe ORM, query builder, code generation
---

# ORM

Type-safe ORM for Dart using code generation.

## Why aim_orm?

- **Type-Safe** - Compile-time type checking for queries
- **Code Generation** - Query builders generated from schema definitions
- **Dart 3 Records** - Modern syntax for table definitions
- **SQL-like API** - Familiar patterns for database operations

## Not Yet Supported

The following are planned but not yet implemented:

- **Relations** - 1:1, 1:N, N:N relations and eager loading
- **SQLite** - `aim_orm` targets PostgreSQL only today; there is no ORM
  implementation for [`aim_sqlite`](/database/drivers/sqlite), which supports
  raw SQL only

## Packages

| Package | Description |
|---------|-------------|
| `aim_orm` | ORM abstraction layer (Column types, conditions) |
| `aim_orm_postgres` | PostgreSQL implementation |
| `aim_orm_codegen` | Code generator (build_runner) |

## Quick Start

### 1. Install

```yaml
# pubspec.yaml
dependencies:
  aim_orm: ^0.4.0
  aim_orm_postgres: ^0.4.0
  aim_postgres: ^0.4.0

dev_dependencies:
  build_runner: ^2.4.0
  aim_orm_codegen: ^0.4.0
```

### 2. Define Schema

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

### 3. Generate Code

```bash
dart run build_runner build
```

### 4. Query

```dart
void main() async {
  final db = await PostgresDatabase.connect(
    'postgres://user:pass@localhost:5432/mydb',
  );

  // Type-safe queries
  final allUsers = await db.users.select();

  for (var user in allUsers) {
    print(user.name);  // Type-safe access
  }

  await db.close();
}
```

## Documentation

- [Schema Definition](/database/orm/schema) - Tables, columns, and modifiers
- [SELECT](/database/orm/select) - Query data
- [INSERT](/database/orm/insert) - Insert data
- [UPDATE](/database/orm/update) - Update data
- [DELETE](/database/orm/delete) - Delete data
- [Transactions](/database/orm/transactions) - Atomic operations
- [Migrations](/database/orm/migrations) - Database migrations with CLI
- [Code Generation](/database/orm/codegen) - Setup and generated code