---
title: aim_database - Database Packages for Dart
description: Database abstraction layer and drivers for Dart. PostgreSQL native driver, ORM, and more. Works independently of aim_server.
head:
  - - meta
    - name: keywords
      content: Dart database, PostgreSQL Dart, Dart ORM, aim_database, aim_postgres
---

# Database

Database packages for Dart. **Works independently of aim_server.**

## Packages

| Package | Description | Version |
|---------|-------------|---------|
| aim_database | Database abstraction layer | 0.0.1 |
| aim_postgres | PostgreSQL native driver | 0.0.1 |
| aim_orm | ORM abstraction layer | Coming Soon |
| aim_orm_postgres | PostgreSQL ORM implementation | Coming Soon |

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
    final id = int.parse(c.param('id')!);
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

### aim_orm + aim_orm_postgres (Coming Soon)

- `aim_orm`: ORM abstraction layer
- `aim_orm_postgres`: PostgreSQL ORM implementation
- Type-safe model definitions
- Query builder
- Relations (1:1, 1:N, N:N)
- Migrations

## Next Steps

- [Installation](/database/installation) - Setup guide
- [PostgreSQL](/database/drivers/postgres) - PostgreSQL driver details
- [ORM](/database/orm/) - ORM documentation (Coming Soon)
