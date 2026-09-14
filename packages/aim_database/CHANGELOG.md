## Unreleased

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