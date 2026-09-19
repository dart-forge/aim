# aim_sqlite

A native SQLite driver for Dart. Talks to libsqlite3 over `dart:ffi` from worker isolates, so a statement never blocks the event loop.

[Documentation](https://aim-dart.dev/database/drivers/sqlite) | [pub.dev](https://pub.dev/packages/aim_sqlite)

## Overview

`aim_sqlite` implements `aim_database`'s `Database` / `Transaction` contract for SQLite. Every statement runs on a worker isolate rather than the caller's, because SQLite's C API blocks the thread it is called on. One isolate holds the only connection that may write; by default, four more each hold a read-only connection, and the database runs in WAL mode so reads and the writer never block each other.

This README and the [docs site page](https://aim-dart.dev/database/drivers/sqlite) describe the same driver in the same order and are kept in sync by hand; an edit to one belongs in the other.

## Installation

```yaml
dependencies:
  aim_sqlite: ^0.1.0
```

`aim_sqlite` does not bundle libsqlite3; see [libsqlite3](#libsqlite3) below for where it looks for it.

## Opening a database

```dart
import 'package:aim_sqlite/aim_sqlite.dart';

final db = await SqliteDatabase.open('app.db');
// ...
await db.close();
```

`path` may also be `:memory:`, or a `file:` URI (including the `file::memory:` and `file:app.db?mode=memory` spellings of an in-memory database):

```dart
final db = await SqliteDatabase.open(':memory:');
```

`open()` takes:

| Parameter | Default | Meaning |
|---|---|---|
| `readers` | `4` | Read-only connections opened alongside the one writer. Forced to `0` for an in-memory database, since such a database is private to the connection that opened it and there is nothing for a second connection to share. |
| `busyTimeout` | 5 seconds | How long SQLite waits for a lock another connection holds on the file before giving up with `SQLITE_BUSY`. |
| `acquireTimeout` | 30 seconds | How long a read waits for a reader connection to come free before failing with `SqliteTimeoutException`. |
| `synchronous` | `SqliteSynchronous.full` | `PRAGMA synchronous`, applied to the writer. `.full` survives a power loss; `.normal` is faster but loses the most recent commits on one (in WAL mode, a crash of the process alone is still safe either way). |
| `libraryPath` | `null` | An explicit path to libsqlite3. See [libsqlite3](#libsqlite3). |

You can also open a file-backed database with `readers: 0`; every read then goes through the writer connection as well, the same as an in-memory database does.

## Concurrency model

One writer isolate, and by default four reader isolates, all talking to the same file in WAL mode:

- Writes always go to the one writer, because SQLite allows only one at a time. Reads are spread across the readers, so they run alongside each other and alongside the writer -- a write never blocks a read.
- `transaction()` holds the writer for as long as its body runs. Reads keep running while it does; in WAL mode they see the snapshot from before the transaction started, not its uncommitted writes.
- Which connection a statement lands on is decided by its leading keyword (`SELECT` and friends go to a reader) and then checked again once it gets there, so a write the keyword did not give away -- `WITH ... INSERT`, or a batch led by a `SELECT` with a write further along -- is never stepped by a reader; it is handed back to the writer instead.

```dart
final stats = db.stats;
```

`stats` is a snapshot (`SqliteStats`) with `readers`, `busyReaders`, `queued` (reads waiting for a reader), and `writerBusy`.

### Await a write before reading what it wrote

A read goes straight to its own reader connection; it does not queue behind the writer. A write and a read issued back to back without awaiting the write first are two statements on two different connections, and the read can win the race:

```dart
db.execute('CREATE TABLE t (a INTEGER)'); // not awaited
final rows = await db.query('SELECT * FROM t'); // may run before the CREATE TABLE
```

The query above may return before the table exists at all, and fail with "no such table". Awaiting the write is all it takes:

```dart
await db.execute('CREATE TABLE t (a INTEGER)');
final rows = await db.query('SELECT * FROM t'); // guaranteed to see it
```

This is a different thing from the snapshot a reader takes while a transaction holds the writer, which is deliberate and cannot be changed by awaiting from outside the transaction.

### Inside a transaction, use `tx`

A call on the database itself -- `db.query`, `db.execute`, or `db.transaction` -- made from inside a `transaction()` body is refused with a `StateError` instead of being queued, because queuing it would wait for the lease the body itself is holding, which cannot come free until the body returns:

```dart
await db.transaction((tx) async {
  await tx.execute('INSERT INTO t VALUES (1)'); // do this
  // db.query(...), db.execute(...), and db.transaction(...) would each
  // throw StateError here instead of running.
});
```

A concurrent call from anywhere else in the program is not affected by this: it queues for the writer normally and runs after the transaction commits or rolls back.

## Queries

### Named parameters

```dart
final rows = await db.query(
  'SELECT * FROM users WHERE active = :active',
  params: {'active': true},
);
```

### Positional parameters

```dart
final rows = await db.query('SELECT * FROM users WHERE id = ?', args: [1]);
```

A single statement takes either `args` or `params`, never both, and a wrong number of positional arguments -- or a named parameter the statement does not declare -- throws `ArgumentError`.

## Type mapping

SQLite stores only five storage classes and has no separate date, boolean, or JSON type. The column's **declared type** is the only hint the driver gets, and it decides what Dart type a value comes back as:

| Declared type | Dart |
|---|---|
| `INTEGER`, `INT`, `BIGINT`, `SMALLINT`, `TINYINT` | `int` |
| `REAL`, `DOUBLE`, `DOUBLE PRECISION`, `FLOAT` | `double` |
| `NUMERIC`, `DECIMAL` | `String` -- kept as text, never a `double`, so money survives |
| `BOOLEAN`, `BOOL` | `bool`, from the stored `0` / `1` |
| `TEXT`, `VARCHAR`, `CHAR`, `CLOB`, `UUID` | `String` |
| `TIMESTAMP`, `DATETIME`, `DATE` | `DateTime`, always UTC |
| `JSON`, `JSONB` | result of `jsonDecode` |
| `BLOB` | `Uint8List` |

Declared types are matched case-insensitively with any size or precision dropped, so `varchar(255)` and `VARCHAR(255)` both match the `VARCHAR` row above.

**A column with no declared type at all comes back as its raw storage class, unconverted** -- whatever `int`, `double`, `String`, `Uint8List`, or `null` SQLite actually stored. This includes every expression and most aggregates, which have no declared type of their own, and it is the one gotcha worth designing around:

```dart
await db.execute('CREATE TABLE events (created_at TIMESTAMP)');
await db.execute(
  'INSERT INTO events (created_at) VALUES (:createdAt)',
  params: {'createdAt': DateTime.utc(2026, 9, 19)},
);

await db.query('SELECT created_at FROM events');           // -> DateTime
await db.query('SELECT max(created_at) AS m FROM events'); // -> String, because max() has no declared type
```

A declared type this driver does not recognize (anything not in the table above) falls back to the raw storage class the same way. A `BOOLEAN` column holding anything other than `0` or `1` fails to decode instead of guessing.

### DateTime

Written as ISO 8601 text in UTC. Read back from:

- **TEXT** -- any ISO 8601 string. One with no time zone offset is treated as a UTC wall clock, not local time.
- **INTEGER** -- unix epoch seconds, what `unixepoch()` / `strftime('%s', ...)` produce.
- **REAL** -- a Julian day, what SQLite's date functions produce by default.

Every `DateTime` this driver returns has `isUtc == true`.

### Parameter types

| Dart | Stored as |
|---|---|
| `null` | `NULL` |
| `int` | `INTEGER` |
| `double` | `REAL` |
| `bool` | `INTEGER` (`0` or `1`) |
| `String` | `TEXT` |
| `Uint8List` | `BLOB` |
| `DateTime` | `TEXT`, ISO 8601 in UTC |
| `Map`, `List` | `TEXT`, JSON |

SQLite has no array type, so a `List` can only be sent as JSON -- unlike the Postgres driver, there is no array-literal option to choose between.

Anything not in this table throws `ArgumentError` naming the parameter, rather than falling back to `Object.toString()`. SQLite would accept the resulting string without complaint, and the mistake would only turn up later as wrong data.

## Execute

```dart
final inserted = await db.execute(
  'INSERT INTO users (name) VALUES (:name)',
  params: {'name': 'Alice'},
); // 1
```

`execute()` always goes to the writer, even for a statement that only reads -- it does not consult the read/write routing that `query()` uses. A statement that changes nothing (most DDL, for instance) returns `0`. Running several `;`-separated statements in one call sums their counts.

## Transactions

```dart
await db.transaction((tx) async {
  await tx.execute(
    'UPDATE accounts SET balance = balance - :amount WHERE id = :from',
    params: {'amount': 100, 'from': 1},
  );
  await tx.execute(
    'UPDATE accounts SET balance = balance + :amount WHERE id = :to',
    params: {'amount': 100, 'to': 2},
  );
  // Committed if the body returns; rolled back, and the error rethrown,
  // if it throws.
});
```

The transaction takes the write lock immediately (`BEGIN IMMEDIATE`) rather than at its first write, so it fails up front if the lock is not available instead of partway through the body. See [Inside a transaction, use tx](#inside-a-transaction-use-tx) above for the rule about calling `tx`, not `db`, from within the body.

## Limits

- **`CREATE TEMP TABLE` does not work on the read path.** A reader connection prepares an entire multi-statement batch before running any of it, to decide up front whether the whole batch only reads. A later statement that depends on an earlier one having already run cannot be prepared yet, so `SELECT 1; CREATE TEMP TABLE t AS SELECT 1; SELECT * FROM t` fails with "no such table" as a single `query()` call, even though the same three statements work fine one at a time, or through `execute()` / a transaction, which run the writer's connection one statement at a time instead.
- **A parameterized call cannot carry a placeholder past the first statement of a batch.** `db.execute('INSERT INTO t VALUES (?); INSERT INTO t VALUES (?)', args: [1])` throws `ArgumentError` as soon as the second statement is reached. **That refusal is not a rollback**: statements run one at a time, so everything before the refused statement has already run and been committed. Running the same call again would apply it a second time. Wrap a batch that must be all-or-nothing in `db.transaction()` instead.
- **An in-memory database has no readers.** Every connection to `:memory:` (or its `file:` URI spellings) is a private, empty database of its own, so there is nothing for a second connection to share; `readers` is forced to `0` and reads run on the writer connection too.
- **The database's directory must be writable, even for a connection opened read-only.** WAL keeps a shared index (a `-shm` file) next to the database file, and only a connection that may write can create or extend it. A read-only filesystem is not supported.

## `busyTimeout` vs `acquireTimeout`

Two different waits, at two different layers:

- **`busyTimeout`** is SQLite itself waiting for a lock on the database file, held by another connection -- typically another process, or this driver's own writer mid-transaction.
- **`acquireTimeout`** is this driver waiting for a free reader isolate to run a read on. It bounds nothing else: not a statement that is already running (an FFI call cannot be interrupted once started), and not the writer's queue, which is deliberately unbounded -- a statement waiting behind a long transaction is behaving correctly, and failing it would turn ordinary contention into a spurious error.

A single read can therefore cost, at worst, the two timeouts summed, plus however long the statement itself takes.

```dart
final db = await SqliteDatabase.open(
  'app.db',
  busyTimeout: Duration(seconds: 10),
  acquireTimeout: Duration(seconds: 5),
);
```

## libsqlite3

`aim_sqlite` does not bundle libsqlite3; it loads whatever is already on the machine, trying in order:

1. `libraryPath` passed to `SqliteDatabase.open()`, if any -- tried alone, with no fallback.
2. The `AIM_SQLITE_LIBRARY` environment variable, if set.
3. The platform default: `libsqlite3.dylib` on macOS, `sqlite3.dll` on Windows, or `libsqlite3.so.0` then `libsqlite3.so` on Linux.

**libsqlite3 3.8.7 or newer is required.** That floor comes from `sqlite3_malloc64`, the newest function the driver calls -- not from WAL support, which is older still. Opening with an older library fails, naming the version that was found.

## Error handling

```dart
try {
  await db.execute('INSERT INTO users (id) VALUES (1)');
} on SqliteException catch (e) {
  print('SQLite error ${e.resultCode}: ${e.message}');
}
```

- `SqliteException` -- a statement failed inside SQLite. Carries `extendedResultCode` (e.g. `2067` for `SQLITE_CONSTRAINT_UNIQUE`) and `resultCode`, its low 8 bits, so you can branch on the failure without matching on `message`.
- `SqliteDecodeException` -- a column's value could not become the Dart type its declared type promises (an unparsable `BOOLEAN`, for instance). Names the `column`, the `declType`, and the `rawValue` that failed to decode.
- `SqliteTimeoutException` -- a read waited longer than `acquireTimeout` for a reader to come free. Nothing ran, so running the same call again repeats nothing.

## Scope

This driver executes raw SQL through `Database` / `Transaction` only. The ORM (`aim_orm`) and the `aim db:*` migration commands work with PostgreSQL today; neither supports SQLite yet. Use raw SQL and manage your own schema -- for example with `CREATE TABLE IF NOT EXISTS` at startup -- until that changes.

## Documentation

For more detail and a complete example, see the [documentation](https://aim-dart.dev/database/drivers/sqlite).
