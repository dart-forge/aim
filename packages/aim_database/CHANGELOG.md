## 0.4.0

- New: `scanSqlPlaceholders` finds the `:name` and `?` parameter
  placeholders in a statement and skips the ones inside a string literal, a
  quoted identifier or a comment. `SqlDialect` carries the three rules that
  differ between PostgreSQL and MySQL — which character quotes an
  identifier, whether a backslash escapes inside a literal, and whether `#`
  starts a comment. A driver rewrites the placeholders into its own form;
  finding them is shared.

## 0.3.0

- Document the value contract on `Database` / `Transaction`: drivers return
  Dart-typed values, `DateTime` is always UTC, `execute()` returns affected rows.

## 0.2.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.2.0)

## 0.1.1

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.1.1)


## 0.1.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/v0.1.0)


## 0.0.1

- Initial release of `aim_database` package
- Added `Database` abstract class with `query()`, `execute()`, `transaction()`, and `close()` methods
- Added `Transaction` abstract class with `query()` and `execute()` methods
- Support for named parameters (`:name`) and positional arguments (`$1`)