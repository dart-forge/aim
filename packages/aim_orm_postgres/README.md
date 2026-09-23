# aim_orm_postgres

PostgreSQL ORM implementation for Dart.

[Documentation](https://aim-dart.dev/database/orm/) | [pub.dev](https://pub.dev/packages/aim_orm_postgres)

## Overview

`aim_orm_postgres` provides a complete ORM solution for PostgreSQL databases. Define your tables using Dart's Record syntax and get type-safe query builders generated automatically with `build_runner`. Supports SELECT, INSERT, UPDATE, DELETE operations with fluent API, WHERE, LIMIT, OFFSET clauses, transactions, and PostgreSQL-specific types like UUID, SERIAL, and JSONB.

## Installation

```yaml
dependencies:
  aim_orm_postgres: ^0.4.0
  aim_postgres: ^0.4.0

dev_dependencies:
  aim_orm_codegen: ^0.4.0
  build_runner: ^2.4.0
```

## Documentation

For detailed usage, examples, and API reference, see the [documentation](https://aim-dart.dev/database/orm/).
