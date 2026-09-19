---
title: SQLite Driver - Aim Database
description: Native SQLite driver for Dart. dart:ffi worker isolates, WAL concurrency, and a documented type mapping.
head:
  - - meta
    - name: keywords
      content: Dart SQLite, aim_sqlite, SQLite driver, dart:ffi, WAL
---

# SQLite

Native SQLite driver for Dart. Talks to libsqlite3 over `dart:ffi` from worker isolates, so a statement never blocks the event loop.

This page and the package [README](https://github.com/dart-forge/aim/blob/main/packages/aim_sqlite/README.md) describe the same driver in the same order and are kept in sync by hand; an edit to one belongs in the other.

## Features

- Native `dart:ffi` bindings to libsqlite3 -- no bundled binary, no external process
- Every statement runs on a worker isolate, off the event loop
- One writer connection and, by default, four read-only reader connections, in WAL mode
- Named parameters (`:name`) and positional parameters (`?`)
- A documented mapping from SQLite's declared types to Dart types, including `DateTime`
- Transaction support with automatic commit and rollback

## Installation

```bash
dart pub add aim_sqlite
```

This also adds `aim_database` as a dependency. `aim_sqlite` does not bundle libsqlite3 -- see [libsqlite3](#libsqlite3) for where it looks for it.

## Opening a Database

### A File

```dart
import 'package:aim_sqlite/aim_sqlite.dart';

final db = await SqliteDatabase.open('app.db');
```

### In Memory

```dart
final db = await SqliteDatabase.open(':memory:');
```

The `file::memory:` and `file:app.db?mode=memory` URI spellings of an in-memory database are recognized the same way.

### Options

```dart
final db = await SqliteDatabase.open(
  'app.db',
  readers: 8,
  busyTimeout: Duration(seconds: 10),
  synchronous: SqliteSynchronous.normal,
);
```

| Parameter | Default | Meaning |
|---|---|---|
| `readers` | `4` | Read-only connections opened alongside the one writer. Forced to `0` for an in-memory database, since such a database is private to the connection that opened it and there is nothing for a second connection to share. |
| `busyTimeout` | 5 seconds | How long SQLite waits for a lock another connection holds on the file before giving up with `SQLITE_BUSY`. |
| `acquireTimeout` | 30 seconds | How long a read waits for a reader connection to come free. See [Timeouts](#busytimeout-vs-acquiretimeout). |
| `synchronous` | `SqliteSynchronous.full` | `PRAGMA synchronous`, applied to the writer. `.full` survives a power loss; `.normal` is faster but loses the most recent commits on one (in WAL mode, a crash of the process alone is still safe either way). |
| `libraryPath` | `null` | An explicit path to libsqlite3. See [libsqlite3](#libsqlite3). |

### Concurrency Model

One writer isolate, and by default four reader isolates, all talking to the same file in WAL mode:

- Writes always go to the one writer -- SQLite allows only one at a time. Reads are spread across the readers, so they run alongside each other and alongside the writer: a write never blocks a read.
- `transaction()` holds the writer for as long as its body runs. Reads keep running while it does; in WAL mode they see the snapshot from before the transaction started, not its uncommitted writes.
- Which connection a statement lands on is decided by its leading keyword first, then checked again once it gets there, so a write the keyword did not give away is never stepped by a reader -- it is handed back to the writer instead.

```dart
final stats = db.stats;
```

`db.stats` returns a snapshot with `readers`, `busyReaders`, `queued` (reads waiting for a reader), and `writerBusy`.

#### Await a write before reading what it wrote

A read goes straight to its own reader connection rather than queueing behind the writer. A write and a read issued back to back without awaiting the write first are two statements on two different connections, and the read can win the race, returning before the write has applied -- or failing with "no such table" if the write was the `CREATE TABLE`:

```dart
await db.execute('CREATE TABLE t (a INTEGER)');
final rows = await db.query('SELECT * FROM t'); // guaranteed to see it
```

Awaiting the write is all it takes. This is separate from the snapshot a reader takes while a transaction holds the writer, which is deliberate and is not affected by awaiting from outside the transaction.

#### Inside a transaction, use `tx`

A call on the database itself -- `db.query`, `db.execute`, or `db.transaction` -- made from inside a `transaction()` body is refused with a `StateError` instead of being queued: queueing it would wait for the lease its own body is holding, which cannot come free until the body returns.

```dart
await db.transaction((tx) async {
  await tx.execute('INSERT INTO t VALUES (1)'); // do this
  // db.query(...), db.execute(...), and db.transaction(...) would each
  // throw StateError here instead of running.
});
```

A concurrent call from anywhere else in the program queues for the writer normally and runs after the transaction commits or rolls back; the refusal only applies to a call made from inside the very transaction it would wait for.

## Queries

### Named Parameters

```dart
final users = await db.query(
  'SELECT * FROM users WHERE status = :status AND age > :age',
  params: {'status': 'active', 'age': 18},
);

for (final row in users) {
  print('${row['name']} (${row['email']})');
}
```

### Positional Parameters

```dart
final users = await db.query('SELECT * FROM users WHERE id = ?', args: [123]);
```

A single statement takes either `args` or `params`, never both. A wrong number of positional arguments, or a named parameter the statement does not declare, throws `ArgumentError`.

### Simple Query (no parameters)

```dart
final result = await db.query('SELECT sqlite_version() AS v');
print(result.first['v']);
```

When a single `query()` call runs several `;`-separated statements, the rows of the last row-returning statement are returned; use `execute()` for the summed row count.

## Type Mapping

SQLite stores only five storage classes and has no separate date, boolean, or JSON type. A column's **declared type** is the only hint the driver gets, and it decides what Dart type a value comes back as:

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

Declared types are matched case-insensitively with any size or precision dropped, so `varchar(255)` and `VARCHAR(255)` both match `VARCHAR` above.

**A column with no declared type at all comes back as its raw storage class, unconverted.** Every expression and most aggregates have no declared type, which makes this the one gotcha worth designing around:

```dart
await db.execute('CREATE TABLE events (created_at TIMESTAMP)');
await db.execute(
  'INSERT INTO events (created_at) VALUES (:createdAt)',
  params: {'createdAt': DateTime.utc(2026, 9, 19)},
);

await db.query('SELECT created_at FROM events');           // -> DateTime
await db.query('SELECT max(created_at) AS m FROM events'); // -> String: max() has no declared type
```

A declared type this driver does not recognize falls back to the raw storage class the same way. A `BOOLEAN` column holding anything other than `0` or `1` fails to decode instead of guessing.

### DateTime

Written as ISO 8601 text in UTC. Read back from:

- **TEXT** -- any ISO 8601 string. One with no time zone offset is treated as a UTC wall clock, not local time.
- **INTEGER** -- unix epoch seconds, what `unixepoch()` / `strftime('%s', ...)` produce. Always seconds, never milliseconds: a column holding milliseconds -- what Java, Android and JavaScript write -- does not fail, it decodes to a date tens of thousands of years out (`1758243723000` reads as the year 57686). To read such a column, select it through an expression (`created_at + 0`), which has no declared type and so comes back as the stored `int`.
- **REAL** -- a Julian day, what SQLite's date functions produce by default.

Every `DateTime` this driver returns has `isUtc == true`.

### Parameters

Parameters accept:

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

SQLite has no array type, so a `List` can only be sent as JSON -- unlike the PostgreSQL driver, there is no array-literal option to choose between.

```dart
await db.execute(
  'INSERT INTO posts (tags, meta) VALUES (:tags, :meta)',
  params: {
    'tags': ['dart', 'sqlite'], // stored as JSON text
    'meta': {'draft': true},   // stored as JSON text
  },
);
```

A value not in the table above throws `ArgumentError` naming the parameter, rather than falling back to `Object.toString()`. SQLite would accept the resulting string without complaint, and the mistake would only turn up later as wrong data.

## Execute

Use `execute()` for `INSERT`, `UPDATE`, `DELETE`, and DDL. It returns the number of affected rows:

```dart
final inserted = await db.execute(
  'INSERT INTO users (name) VALUES (:name)',
  params: {'name': 'Alice'},
); // 1

final updated = await db.execute('UPDATE users SET active = 0'); // rows changed
```

`execute()` always goes to the writer, even for a statement that only reads -- it does not consult the read/write routing that `query()` uses. A statement that changes nothing (most DDL, for instance) returns `0`. Running several `;`-separated statements in one call sums their counts. Use `query()` with `RETURNING` when you need the rows themselves.

### Getting the Inserted Row Id

`query()` with a `RETURNING` clause is how to read back what a write produced -- most often the id of a row just inserted. The statement is a write, so it goes to the writer like any other, and the rows it returns come back as the result of the call:

```dart
final inserted = await db.query(
  'INSERT INTO users (name) VALUES (:name) RETURNING id',
  params: {'name': 'Alice'},
);
final id = inserted.single['id'] as int;
```

**`last_insert_rowid()` through `query()` is not to be relied on.** It answers `0` -- not because the insert failed, but because `query()` sends that `SELECT` to one of the read-only connections, which has never inserted anything and so has no last insert row id to report. Awaiting the write first does not help: the value belongs to a connection, not to the database. The one exception makes this worse rather than better -- a database with no readers (`readers: 0`, which every in-memory database is forced to) runs every read on the writer, so the real id does come back there. The same code can work against `:memory:` in a test and answer `0` against the file in production.

Inside a transaction it is a different matter. Every statement on a `tx` runs on the writer connection, so `last_insert_rowid()` there does see the insert the same body just made:

```dart
await db.transaction((tx) async {
  await tx.execute(
    'INSERT INTO users (name) VALUES (:name)',
    params: {'name': 'Alice'},
  );
  final rows = await tx.query('SELECT last_insert_rowid() AS id');
  final id = rows.single['id'] as int;
});
```

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

  // Transaction is automatically committed if no exception is thrown.
  // If an exception is thrown, the transaction is rolled back and the
  // exception is rethrown.
});
```

The transaction takes the write lock immediately (`BEGIN IMMEDIATE`) rather than at its first write, so it fails up front if the lock is not available instead of partway through the body.

### Use `tx`, Not `db`, Inside the Body

Do not call `db.query()`, `db.execute()`, or `db.transaction()` from inside a `transaction()` callback -- each would wait for the very transaction it is running inside of, which cannot finish until it returns, so each is refused with a `StateError` instead. Always go through the `tx` argument for statements that must be part of the transaction. See [Inside a transaction, use tx](#inside-a-transaction-use-tx) above.

## Limits

- **`CREATE TEMP TABLE` does not work on the read path.** A reader connection prepares an entire multi-statement batch before running any of it, to decide up front whether the whole batch only reads. A later statement that depends on an earlier one having already run cannot be prepared yet, so `SELECT 1; CREATE TEMP TABLE t AS SELECT 1; SELECT * FROM t` fails with "no such table" as a single `query()` call, even though the same three statements work fine one at a time, or through `execute()` / a transaction, which run the writer's connection one statement at a time instead.
- **A parameterized call cannot carry a placeholder past the first statement of a batch.** `db.execute('INSERT INTO t VALUES (?); INSERT INTO t VALUES (?)', args: [1])` throws `ArgumentError` as soon as the second statement is reached. **That refusal is not a rollback**: the statements ahead of the refused one have already run. What that leaves behind depends on where they ran -- outside a transaction each of them committed as it went, so running the same call again would apply them a second time; inside `db.transaction()` they are rolled back along with it; and a batch refused on a reader can only have held reads, since one holding a write is handed to the writer before anything runs. Wrap a batch that must be all-or-nothing in `db.transaction()` instead.
- **An in-memory database has no readers.** Every connection to `:memory:` (or its `file:` URI spellings) is a private, empty database of its own, so there is nothing for a second connection to share; `readers` is forced to `0` and reads run on the writer connection too.
- **The database's directory must be writable, even for a connection opened read-only.** WAL keeps a shared index (a `-shm` file) next to the database file, and only a connection that may write can create or extend it. A read-only filesystem is not supported.

## `busyTimeout` vs `acquireTimeout`

Two different waits, at two different layers:

- **`busyTimeout`** is SQLite itself waiting for a lock on the database file, held by another connection -- typically another process, or this driver's own writer mid-transaction.
- **`acquireTimeout`** is this driver waiting for a free reader isolate to run a read on. It bounds nothing else: not a statement that is already running, and not the writer's queue, which is deliberately unbounded -- a statement waiting behind a long transaction is behaving correctly, and failing it would turn ordinary contention into a spurious error.

A single read can therefore cost, at worst, the two timeouts summed, plus however long the statement itself takes.

## libsqlite3

`aim_sqlite` does not bundle libsqlite3; it loads whatever is already on the machine, trying in order:

1. An explicit `libraryPath` passed to `SqliteDatabase.open()` -- tried alone, with no fallback.
2. The `AIM_SQLITE_LIBRARY` environment variable, if set.
3. The platform default: `libsqlite3.dylib` on macOS, `sqlite3.dll` on Windows, or `libsqlite3.so.0` then `libsqlite3.so` on Linux.

**libsqlite3 3.8.7 or newer is required.** That floor comes from `sqlite3_malloc64`, the newest function the driver calls -- not from WAL support, which is older still. Opening with an older library fails with a `SqliteLibraryTooOldException`, naming the version that was found.

## Error Handling

```dart
try {
  await db.execute('INSERT INTO users (id) VALUES (1)');
} on SqliteException catch (e) {
  print('SQLite error ${e.resultCode}: ${e.message}');
} on SqliteDecodeException catch (e) {
  print('could not decode column ${e.column}: ${e.message}');
} on SqliteTimeoutException catch (e) {
  print('no reader became free within ${e.timeout}');
}
```

- `SqliteException` -- a statement failed inside SQLite. Carries `extendedResultCode` (e.g. `2067` for `SQLITE_CONSTRAINT_UNIQUE`) and `resultCode`, its low 8 bits, so you can branch on the failure without matching on `message`.
- `SqliteDecodeException` -- a column's value could not become the Dart type its declared type promises. Names the `column`, the `declType`, and the `rawValue` that failed to decode.
- `SqliteTimeoutException` -- a read waited longer than `acquireTimeout` for a reader to come free. Nothing ran, so retrying repeats nothing.
- `SqliteLibraryNotFoundException` -- no libsqlite3 could be loaded at all, thrown by `SqliteDatabase.open()`. `searched` lists every path that was tried, in order; see [libsqlite3](#libsqlite3) for where that list comes from.
- `SqliteLibraryTooOldException` -- a libsqlite3 was loaded and is older than the 3.8.7 floor. Carries the `path` it came from, the `version` it reported, and the `requiredVersion`. A separate type from the one above on purpose: "no library at all" and "the wrong library" are different problems to fix, so catching one does not catch the other.

## Scope

This driver executes raw SQL through `Database` / `Transaction` only. The [ORM](/database/orm/) (`aim_orm`) and the `aim db:*` migration commands work with PostgreSQL today; neither supports SQLite yet. Use raw SQL and manage your own schema -- for example with `CREATE TABLE IF NOT EXISTS` at startup -- until that changes.

## Best Practices

### 1. Await Writes Before Dependent Reads

```dart
// Good -- the read is guaranteed to see the write
await db.execute('CREATE TABLE t (a INTEGER)');
await db.query('SELECT * FROM t');
```

A read never queues behind the writer, so an un-awaited write and a following read can run in either order. See [Await a write before reading what it wrote](#await-a-write-before-reading-what-it-wrote).

### 2. Use `tx` Inside Transactions

```dart
// Good -- part of the transaction
await db.transaction((tx) async {
  await tx.execute('UPDATE accounts SET balance = balance - 100 WHERE id = 1');
});
```

`db.query()` / `db.execute()` called from inside the callback are refused with a `StateError` rather than silently running outside the transaction.

### 3. Wrap All-or-Nothing Batches in a Transaction

```dart
// Good -- both inserts commit or neither does
await db.transaction((tx) async {
  await tx.execute('INSERT INTO t VALUES (1)');
  await tx.execute('INSERT INTO t VALUES (2)');
});
```

A multi-statement call to `query()` / `execute()` is not atomic across statements the way a transaction is, and a parameterized one cannot carry parameters past its first statement at all. See [Limits](#limits).

### 4. Use Named or Positional Parameters

```dart
// Good -- not vulnerable to SQL injection
await db.query('SELECT * FROM users WHERE name = :name', params: {'name': userInput});

// Bad -- SQL injection risk
await db.query("SELECT * FROM users WHERE name = '$userInput'");
```

## Complete Example

```dart
import 'package:aim_sqlite/aim_sqlite.dart';

void main() async {
  final db = await SqliteDatabase.open('app.db');

  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        created_at TIMESTAMP NOT NULL
      )
    ''');

    final inserted = await db.query(
      'INSERT INTO users (name, created_at) VALUES (:name, :createdAt) '
      'RETURNING id',
      params: {'name': 'Alice', 'createdAt': DateTime.now().toUtc()},
    );
    final id = inserted.single['id'] as int;

    final users = await db.query('SELECT * FROM users');
    for (final user in users) {
      print('${user['id']}: ${user['name']} (${user['created_at']})');
    }

    await db.transaction((tx) async {
      await tx.execute(
        'UPDATE users SET name = :name WHERE id = :id',
        params: {'name': 'Alice Updated', 'id': id},
      );
    });
  } finally {
    await db.close();
  }
}
```

## Next Steps

- [Database Overview](/database/) - All database packages
- [PostgreSQL](/database/drivers/postgres) - the driver to use today for the ORM or migrations
