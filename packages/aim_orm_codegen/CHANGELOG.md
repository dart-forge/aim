## Unreleased

### Breaking

- Generated row mappers cast typed driver values (`row['id'] as int`,
  `row['created_at'] as DateTime`) instead of parsing strings. Requires the
  matching `aim_postgres` release; regenerate with `build_runner`.
- `DateTime` fields are UTC (see `aim_postgres`).

## 0.2.0

- Requires analyzer ^14.0.0, source_gen ^4.3.0, build ^4.0.11; compatible with build_runner 2.16.

## 0.1.1

See [Release Notes](https://github.com/aim-dart/aim/releases/tag/0.1.1)


## 0.1.0

See [Release Notes](https://github.com/aim-dart/aim/releases/tag/v0.1.0)


## 0.0.1

Initial release of aim_orm_codegen - Code generation for aim_orm.

### Features

- Record Syntax Support:
  - `@PgTable` annotation processing
  - Dart Record field analysis
  - Column type detection (integer, varchar, text, timestamp, uuid, serial, jsonb)
- Generated Code:
  - Row typedef with named fields
  - QueryBuilder class for table access
  - SelectBuilder with WHERE, LIMIT, OFFSET support
  - InsertBuilder with type-safe values
  - UpdateBuilder with SET and WHERE
  - DeleteBuilder with WHERE
  - PostgresDatabase extension methods
  - PostgresTransaction extension methods
- Builders:
  - `record_pg_table` - For Record syntax with `@PgTable`
  - `table` - For class-based definitions (legacy)

### Supported

- Dart SDK: `^3.10.0`
- build_runner: `^2.4.0`
- analyzer: `^10.0.1`

### What's Included

- `RecordPgTableGenerator` - Main generator for Record syntax tables
- `TableGenerator` - Generator for class-based tables
- Builder configuration for build_runner integration
