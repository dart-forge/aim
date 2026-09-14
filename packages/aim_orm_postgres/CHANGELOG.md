## 0.2.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.2.0)

## 0.1.1

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.1.1)


## 0.1.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/v0.1.0)


## 0.0.1

Initial release of aim_orm_postgres - PostgreSQL ORM implementation for Dart.

### Features

- Record Syntax Table Definitions:
  - `@PgTable` annotation for table declaration
  - Type-safe column definitions using Dart Records
- PostgreSQL Column Types:
  - `uuid()` - UUID type
  - `serial()` - Auto-increment integer
  - `jsonb<T>()` - JSONB with generic type support
- Foreign Key Support:
  - `references()` - Define foreign key relationships
  - `OnDeleteAction` - CASCADE, SET NULL, RESTRICT, NO ACTION
- Code Generation:
  - Automatic query builder generation
  - Type-safe Row typedefs
  - PostgresDatabase extension methods
  - PostgresTransaction extension methods

### CRUD Operations

- SELECT with WHERE, LIMIT, OFFSET
- INSERT with type-safe values
- UPDATE with SET and WHERE
- DELETE with WHERE

### Supported

- Dart SDK: `^3.10.0`
- PostgreSQL: All versions supported by aim_postgres

### What's Included

- `PgTable` annotation class
- PostgreSQL-specific column types (SerialColumn, UuidColumn, JsonbColumn)
- Column builder functions (serial, uuid, jsonb)
- Integration with aim_orm_codegen for code generation
