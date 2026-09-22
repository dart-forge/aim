# aim_mysql

A pure Dart MySQL driver, implementing the wire protocol directly with no
native dependency. Targets MySQL 8.0 and 8.4.

[pub.dev](https://pub.dev/packages/aim_mysql)

## Overview

`aim_mysql` implements `aim_database`'s `Database` / `Transaction` contract
for MySQL. It supports TLS with certificate verification, the
`caching_sha2_password` and `mysql_native_password` authentication plugins,
prepared statements with a per-connection cache, named (`:name`) and
positional (`?`) parameter binding, and transactions with automatic
rollback.

## Installation

```yaml
dependencies:
  aim_mysql: ^0.4.0
```

## Connecting

```dart
import 'package:aim_mysql/aim_mysql.dart';

final db = await MySqlDatabase.connect(
  'mysql://user:password@localhost:3306/mydb',
);
```

The connection string is `mysql://user:password@host:port/database`. `port`
defaults to `3306`. Leaving out the path (or giving just `/`) selects no
database at all, which is different from a database whose name is the
empty string.

## Connection pooling

`MySqlDatabase.connect()` opens a pool of connections, not a single one. One
connection is opened immediately, so a bad connection string or a rejected
password surfaces from `connect()` itself; the rest are opened on demand.

```dart
final db = await MySqlDatabase.connect(
  'mysql://user:password@localhost:3306/mydb',
  maxConnections: 20,
  acquireTimeout: Duration(seconds: 5),
);
```

| Parameter | Default | Meaning |
|---|---|---|
| `maxConnections` | `10` | Upper bound on open connections. |
| `acquireTimeout` | 30s | How long a call waits for a free connection before throwing `PoolTimeoutException`. |
| `idleTimeout` | 10min | Idle connections unused for this long are closed. `Duration.zero` disables. |
| `maxLifetime` | 30min | Connections older than this are closed once idle. `Duration.zero` disables. |
| `validationInterval` | 30s | Idle connections unused for at least this long are pinged before reuse. `Duration.zero` pings every time. |

Each `query()` / `execute()` / `insert()` borrows a connection for the call
and returns it when done; `transaction()` pins one connection for the whole
callback. `db.poolStats` returns a `PoolStats` snapshot.

**`db.query()` / `db.execute()` called from inside a `transaction()`
callback run on a different pooled connection and are not part of that
transaction.** Use the `tx` argument the callback is given for everything
that must be atomic -- this is also why `SELECT LAST_INSERT_ID()` behaves
the way described under [Execute](#execute) below.

## TLS

`sslmode` is a connection-string parameter:
`mysql://user:password@host/db?sslmode=require`. **It defaults to
`prefer`, not `disable`** -- leaving it out must not silently produce a
plaintext connection to a network database.

| Mode | Behaviour |
|---|---|
| `disable` | Never use TLS. |
| `prefer` (default) | Use TLS if the server offers it, plaintext otherwise. Does not verify the certificate. |
| `require` | Always use TLS; refuse to connect if the server does not offer it. Does not verify the certificate. |
| `verify-ca` | `require`, plus verify the certificate against a trusted CA. |
| `verify-full` | `require`, plus verify the certificate against a trusted CA and that it names the host being connected to. |

**`verify-ca` and `verify-full` behave identically.** Dart's TLS stack has
no way to check a certificate's CA without also checking that it names the
host being connected to, so there is no weaker check for `verify-ca` to
offer than what `verify-full` already does.

A CA file to trust, for `verify-ca` and `verify-full`, is the `sslrootcert`
parameter: `?sslmode=verify-full&sslrootcert=/path/to/ca.crt`.

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

A single statement takes either `args` or `params`, never both --
combining a positional `?` with named parameters in the same statement
throws `ArgumentError`. A name used more than once in the SQL is bound once
per occurrence, from the same value in `params`; a name the SQL does not
use is simply not sent, and a name the SQL uses but `params` has no value
for throws `ArgumentError` naming it.

## `sql_mode`

The driver reads the session's `sql_mode` once when the connection opens,
and again whenever your own SQL changes it (any `SET` statement mentioning
`sql_mode`); it never sets `sql_mode` itself. This matters because
`NO_BACKSLASH_ESCAPES` changes where a string literal ends, which changes
which `:name`-shaped sequences in a statement are placeholders rather than
text inside a string -- so the driver has to know which rule is in effect
before it can scan a statement's placeholders correctly.

## Type mapping

| MySQL type | Dart |
|---|---|
| `TINYINT` | `int`, or `bool` for `BOOL` / `TINYINT(1)` |
| `SMALLINT`, `YEAR` | `int` |
| `MEDIUMINT`, `INT` | `int` |
| `BIGINT` | `int` (throws if `UNSIGNED` and the value is at or above 2^63) |
| `FLOAT` | `double` |
| `DOUBLE` | `double` |
| `DECIMAL`, `NUMERIC` | `String` |
| `DATE`, `DATETIME`, `TIMESTAMP` | `DateTime`, always UTC |
| `TIME` | `String` |
| `JSON` | result of `jsonDecode` |
| `BIT` | `Uint8List` |
| `CHAR`, `VARCHAR`, `TEXT` (any size) | `String` |
| `BINARY`, `VARBINARY`, `BLOB` (any size) | `Uint8List` |
| `ENUM`, `SET` | `String` |
| anything else (`GEOMETRY`, ...) | `String` |

**`TIME` comes back as a `String`, never a `DateTime`.** MySQL's `TIME` is
a signed duration from -838:59:59 to 838:59:59, not a time of day, and no
time-of-day type holds a value outside 24 hours.

**A zero date -- `0000-00-00`, including an otherwise-real date with a
zero month or day -- raises `MySqlDecodeException` rather than becoming
`null` or year zero.** MySQL stores that value as distinct from SQL
`NULL`; mapping it to either `null` or a real `DateTime` would lose the
distinction the column was recording, not just represent it awkwardly.

Every `DateTime` this driver returns has `isUtc == true`: the session's
`time_zone` is pinned to `+00:00` right after connecting.

### Parameter types

| Dart | Sent as |
|---|---|
| `null` | `NULL` |
| `bool` | `TINYINT` (`0` / `1`) |
| `int` | `BIGINT`, 8 bytes regardless of magnitude |
| `double` | `DOUBLE` |
| `DateTime` | `DATETIME`, converted to UTC first |
| `Uint8List` | `BLOB` |
| `String` | `VARCHAR` |

Anything not in this table -- including `Map` and `List` -- throws
`ArgumentError` naming the value's runtime type, rather than falling back
to `Object.toString()`. There is no automatic JSON encoding for a `JSON`
column's parameters; call `jsonEncode()` yourself and pass the result as a
`String`.

## Execute

```dart
final updated = await db.execute(
  'UPDATE users SET name = :name WHERE id = :id',
  params: {'name': 'Alice', 'id': 1},
); // rows affected
```

`execute()` returns the number of affected rows; a statement that reports
none (most DDL, for instance) returns `0`.

### The auto-increment id

MySQL has no `RETURNING`, so reading back the id an `INSERT` generated has
its own method:

```dart
final id = await db.insert(
  'INSERT INTO users (name) VALUES (:name)',
  params: {'name': 'Alice'},
);
```

**A separate `SELECT LAST_INSERT_ID()` sent through `query()` can come
back `0`, even right after a successful insert.** `LAST_INSERT_ID()` is
scoped to the connection that generated the value, and the pool is free to
run that `SELECT` on a different connection than the one that ran the
`INSERT` -- nothing failed, the `SELECT` simply landed on a connection that
never inserted anything. Use `insert()`, which runs both as a single round
trip on the same connection. A plain `SELECT LAST_INSERT_ID()` through
`tx.query()` does work correctly inside `transaction()`, because the
transaction holds one connection for its entire body.

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

### DDL ends the transaction early

**MySQL commits a transaction implicitly when it runs DDL** -- `CREATE
TABLE`, for instance -- whether or not that statement itself goes on to
succeed. Running DDL inside `transaction()` raises
`MySqlTransactionEndedByDdl` naming the statement, rather than letting the
callback carry on believing a later failure could still undo it: by the
time the driver can react, MySQL has already committed.

The honest part: when the DDL statement **succeeds**, everything before it
-- and it -- is known to be committed. When it **fails**, less is known:
all the driver can tell is that the transaction is gone, not whether that
happened through the same implicit commit or because the server rolled the
whole transaction back for some other reason. `MySqlTransactionEndedByDdl`
is raised either way, but only the success case says a commit happened.

The `ROLLBACK` `db.transaction()` sends once this propagates out of the
callback still runs, but does nothing: there is no open transaction left
for it to act on.

## Authentication

Supported: **`caching_sha2_password`** and **`mysql_native_password`**.
This includes `caching_sha2_password`'s public-key path -- when the server
asks for full authentication (rather than its faster cached form) and the
connection is not encrypted, the password is RSA-encrypted with a public
key the server provides, rather than sent in the clear. **`sha256_password`
is not supported**; a server asking for it fails the connection attempt with
`UnsupportedAuthPlugin`, which names the plugin.

## Limits

- **A few statements cannot be prepared at all.** This driver always runs
  statements as prepared statements, with a cache per connection, and MySQL
  refuses to prepare a handful of them -- `DROP PROCEDURE` and `CREATE
  PROCEDURE` among them -- with errno 1295. That comes back as a
  `MySqlException` with `errorCode` `1295`; run such statements outside
  this driver.

## Error handling

```dart
try {
  await db.execute('INSERT INTO users (id) VALUES (1)');
} on MySqlException catch (e) {
  print('MySQL error ${e.errorCode}: ${e.message}');
}
```

- `MySqlException` -- the server refused the statement. Subtypes for the
  common cases: `MySqlUniqueViolation`, `MySqlNotNullViolation`,
  `MySqlForeignKeyViolation`, `MySqlCheckViolation`, `MySqlDeadlock`,
  `MySqlLockWaitTimeout`, `MySqlAccessDenied`. An errno with no subtype
  still comes back as a plain `MySqlException` carrying that `errorCode`.
- `MySqlTransactionEndedByDdl` -- see [DDL ends the transaction
  early](#ddl-ends-the-transaction-early).
- `MySqlDecodeException` -- a column's bytes were read correctly but do
  not fit the Dart type this driver would return for them (a zero date, or
  a `BIGINT UNSIGNED` at or above 2^63).
- `MySqlProtocolException` -- the driver could not make sense of what the
  server sent. Distinct from the server refusing a statement outright.
- `UnsupportedAuthPlugin` -- thrown from `connect()` when the server asks
  for an authentication plugin this driver does not implement (currently
  just `sha256_password`); see [Authentication](#authentication).

## Scope

This driver executes raw SQL through `Database` / `Transaction` only. The
ORM (`aim_orm`) works with PostgreSQL today; it does not support MySQL yet.
Use raw SQL and manage your own schema until that changes.
