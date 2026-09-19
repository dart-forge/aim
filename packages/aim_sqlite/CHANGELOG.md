## 0.1.0

Initial release. `SqliteDatabase` talks to libsqlite3 over `dart:ffi` from worker isolates, so a statement never blocks the event loop. It runs one writer connection and, by default, four read-only reader connections in WAL mode, with named (`:name`) and positional (`?`) parameters, a declared-type-based mapping from SQLite's storage classes to Dart types (`DateTime` always UTC), and `transaction()` with automatic commit and rollback.
