## 0.3.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.3.0)

## 0.2.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.2.0)

## 0.1.1

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.1.1)


## 0.1.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/v0.1.0)


## 0.0.1

Initial release of aim_orm - A type-safe ORM abstraction layer for Dart.

### Features

- Column Types:
  - `integer()` - Integer column
  - `varchar()` - Variable-length character column with optional length
  - `text()` - Text column for long strings
  - `timestamp()` - Timestamp column for date/time values
- Column Modifiers:
  - `primaryKey()` - Mark column as primary key
  - `unique()` - Add unique constraint
  - `nullable()` - Allow null values
  - `withDefault()` - Set default value
  - `indexed()` - Create index on column
- Condition Operators:
  - `eq` - Equal (=)
  - `gt` - Greater than (>)
  - `lt` - Less than (<)
  - `gte` - Greater than or equal (>=)
  - `lte` - Less than or equal (<=)
  - `inList` - IN clause
- Query Builder Foundation:
  - `QueryFuture` - Base class for async query execution
  - `FutureMixin` - Mixin for Future-like behavior

### Supported

- Dart SDK: `^3.10.0`

### What's Included

- `Table` class for table definitions
- `Column` abstract class and concrete implementations
- Column builder functions
- `Condition` class for WHERE clause building
- Query builder base classes
