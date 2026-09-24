---
title: aim_database - Database Packages for Dart
description: Database abstraction layer and drivers for Dart. PostgreSQL and SQLite native drivers, ORM, and more. Works independently of aim_server.
head:
  - - meta
    - name: keywords
      content: Dart database, PostgreSQL Dart, Dart SQLite, Dart ORM, aim_database, aim_postgres, aim_sqlite
---

# Database

Database packages for Dart. **Works independently of aim_server.**

## Packages

| Package | Description | pub.dev |
|---------|-------------|---------|
| aim_database | Database abstraction layer | Published |
| aim_postgres | PostgreSQL native driver | Published |
| aim_sqlite | SQLite native driver | Not yet published — see [SQLite](/database/drivers/sqlite) |
| aim_orm | ORM abstraction layer | Published |
| aim_orm_postgres | PostgreSQL ORM implementation | Published |
| aim_orm_codegen | ORM code generator (build_runner) | Published |

::: warning `dart:io`-only — not for Workers or Deno
`aim_postgres`, `aim_sqlite`, and the ORM (`aim_orm`/`aim_orm_postgres`)
depend on `dart:io` and run on `aim_server` and on `aim_functions` (Cloud
Functions for Firebase compiles to a native binary, not WebAssembly). They
cannot run inside a Cloudflare Worker or a Deno-based runtime such as
Supabase Edge Functions — both compile to WebAssembly without `dart:io`.
On those, use the platform's own bindings instead (Cloudflare's D1 or
Hyperdrive through `c.env`, for example); see
[Workers limitations](/server/workers#limitations).
:::

## Philosophy

Aim's database packages are **completely independent** from `aim_server`.

```dart
// Works without aim_server
import 'package:aim_postgres/aim_postgres.dart';

void main() async {
  final db = await PostgresDatabase.connect(
    'postgresql://user:pass@localhost:5432/mydb',
  );

  final users = await db.query('SELECT * FROM users');
  print(users);

  await db.close();
}
```

Use it for CLI apps, batch processing, migration tools, and any use case beyond web servers.

## Quick Start

### Installation

```bash
dart pub add aim_postgres
```

### Basic Usage

```dart
import 'package:aim_postgres/aim_postgres.dart';

void main() async {
  // Connect
  final db = await PostgresDatabase.connect(
    'postgresql://user:pass@localhost:5432/mydb?sslmode=require',
  );

  // Query with named parameters
  final users = await db.query(
    'SELECT * FROM users WHERE active = :active',
    params: {'active': true},
  );

  // Query with positional parameters
  final user = await db.query(
    r'SELECT * FROM users WHERE id = $1',
    args: [123],
  );

  // Execute (INSERT, UPDATE, DELETE)
  await db.execute(
    'INSERT INTO users (name, email) VALUES (:name, :email)',
    params: {'name': 'Alice', 'email': 'alice@example.com'},
  );

  // Transaction
  await db.transaction((tx) async {
    await tx.execute('UPDATE accounts SET balance = balance - 100 WHERE id = :from',
      params: {'from': 1});
    await tx.execute('UPDATE accounts SET balance = balance + 100 WHERE id = :to',
      params: {'to': 2});
  });

  await db.close();
}
```

## With aim_server

Of course, you can also use it with `aim_server`:

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:aim_postgres/aim_postgres.dart';

late PostgresDatabase db;

void main() async {
  // Database connection
  db = await PostgresDatabase.connect(
    'postgresql://user:pass@localhost:5432/mydb',
  );

  final app = Aim();

  app.get('/users', (c) async {
    final users = await db.query('SELECT * FROM users');
    return c.json({'users': users});
  });

  app.get('/users/:id', (c) async {
    final id = int.parse(c.param('id'));
    final users = await db.query(
      r'SELECT * FROM users WHERE id = $1',
      args: [id],
    );

    if (users.isEmpty) {
      return c.json({'error': 'Not found'}, statusCode: 404);
    }

    return c.json(users.first);
  });

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
}
```

## Features

### aim_postgres

- Native PostgreSQL Wire Protocol implementation
- SSL/TLS connections (disable, allow, prefer, require, verify-ca, verify-full)
- Authentication methods (cleartext, MD5, SCRAM-SHA-256)
- Named parameters (`:name`) and positional parameters (`$1`)
- Transaction support

### aim_sqlite

- Native `dart:ffi` bindings to libsqlite3, run on worker isolates
- One writer connection and, by default, four read-only reader connections, in WAL mode
- Named parameters (`:name`) and positional parameters (`?`)
- Transaction support
- Raw SQL only for now -- the ORM and `aim db:*` migrations are PostgreSQL-only

### aim_orm + aim_orm_postgres

`aim_orm` and `aim_orm_postgres` are implemented and published on pub.dev.
The ORM targets **PostgreSQL only** today — there is no SQLite or MySQL ORM
implementation yet (`aim_sqlite` supports raw SQL only, see above).

- Tables defined as Dart 3 Record literals with the `@PgTable` annotation
- Type-safe, generated query builders (SELECT, INSERT, UPDATE, DELETE) via
  `aim_orm_codegen` and `build_runner`
- Filtering, pagination, and transactions
- Schema-diff migrations through `aim db:generate` / `db:migrate`

Relations (1:1, 1:N, N:N) and eager loading are not implemented yet — see
[ORM Overview](/database/orm/) for the current scope.

## Next Steps

- [Installation](/database/installation) - Setup guide
- [PostgreSQL](/database/drivers/postgres) - PostgreSQL driver details
- [SQLite](/database/drivers/sqlite) - SQLite driver details (not yet published to pub.dev)
- [ORM](/database/orm/) - ORM documentation
