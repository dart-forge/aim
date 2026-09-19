---
title: Database Installation - Aim
description: Install Aim database packages. PostgreSQL and SQLite drivers, database abstraction layer, and ORM setup guide.
head:
  - - meta
    - name: keywords
      content: Dart database install, aim_postgres setup, aim_sqlite setup, PostgreSQL Dart, SQLite Dart
---

# Installation

## Packages

Aim's database packages can be used independently:

| Package | Use Case |
|---------|----------|
| `aim_database` | Abstraction layer only (for custom driver implementations) |
| `aim_postgres` | PostgreSQL connection (includes `aim_database`) |
| `aim_sqlite` | SQLite connection (includes `aim_database`) |
| `aim_orm` | ORM abstraction layer (Coming Soon) |
| `aim_orm_postgres` | PostgreSQL ORM (includes `aim_orm` + `aim_postgres`) |

## PostgreSQL

In most cases, add the PostgreSQL driver directly:

```bash
dart pub add aim_postgres
```

This also adds `aim_database` as a dependency.

## pubspec.yaml

```yaml
dependencies:
  aim_postgres: ^0.0.1
```

## Verify Installation

```dart
import 'package:aim_postgres/aim_postgres.dart';

void main() async {
  final db = await PostgresDatabase.connect(
    'postgresql://user:pass@localhost:5432/mydb',
  );

  print('Connected to PostgreSQL');

  final result = await db.query('SELECT version()');
  print('Version: ${result.first['version']}');

  await db.close();
}
```

## Connection String Format

```
postgresql://user:password@host:port/database?sslmode=require
```

| Parameter | Description | Default |
|-----------|-------------|---------|
| `user` | Username | required |
| `password` | Password | required |
| `host` | Server hostname | `localhost` |
| `port` | Server port | `5432` |
| `database` | Database name | required |
| `sslmode` | SSL mode | `prefer` |

### SSL Modes

| Mode | Description |
|------|-------------|
| `disable` | No SSL |
| `allow` | Try non-SSL first, then SSL |
| `prefer` | Try SSL first, then non-SSL |
| `require` | SSL required |
| `verify-ca` | SSL + verify CA |
| `verify-full` | SSL + verify CA + hostname |

## SQLite

Add the SQLite driver directly:

```bash
dart pub add aim_sqlite
```

This also adds `aim_database` as a dependency.

### pubspec.yaml

```yaml
dependencies:
  aim_sqlite: ^0.1.0
```

### libsqlite3

Unlike `aim_postgres`, `aim_sqlite` does not talk to a server -- it loads `libsqlite3` from the machine it runs on, so that library must already be installed (it ships with macOS and most Linux distributions; on Windows, place `sqlite3.dll` next to your executable, or point the `AIM_SQLITE_LIBRARY` environment variable at it). Version `3.8.7` or newer is required. See the [SQLite driver](/database/drivers/sqlite#libsqlite3) page for the exact search order.

### Verify Installation

```dart
import 'package:aim_sqlite/aim_sqlite.dart';

void main() async {
  final db = await SqliteDatabase.open('app.db');

  print('Connected to SQLite');

  final result = await db.query('SELECT sqlite_version() AS v');
  print('Version: ${result.first['v']}');

  await db.close();
}
```

## Next Steps

- [PostgreSQL Driver](/database/drivers/postgres) - Detailed usage guide
- [SQLite Driver](/database/drivers/sqlite) - Detailed usage guide
- [ORM](/database/orm/) - Coming Soon
