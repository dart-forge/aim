---
title: MySQL Driver - Aim Database
description: Native MySQL driver for Dart. TLS, caching_sha2_password authentication, named parameters, and transactions.
head:
  - - meta
    - name: keywords
      content: Dart MySQL, aim_mysql, MySQL driver, caching_sha2_password, TLS Dart
---

# MySQL

Native MySQL driver for Dart. Implements the MySQL wire protocol from scratch, with no native dependency. Targets MySQL 8.0 and 8.4.

## Features

- Native MySQL wire protocol implementation, no external dependency
- Targets MySQL 8.0 and 8.4
- TLS connection support, with certificate verification
- Authentication: `caching_sha2_password` and `mysql_native_password`, including the `caching_sha2_password` public-key path
- Always runs statements as prepared statements, with a per-connection cache
- Named parameters (`:name`) and positional parameters (`?`)
- Transaction support with automatic rollback

## Installation

`aim_mysql` is not published to pub.dev yet, so `dart pub add aim_mysql`
does not work. Depend on it from the repository instead:

```yaml
dependencies:
  aim_mysql:
    git:
      url: https://github.com/dart-forge/aim.git
      path: packages/aim_mysql
```

## Connection

### Basic Connection

```dart
import 'package:aim_mysql/aim_mysql.dart';

final db = await MySqlDatabase.connect(
  'mysql://user:password@localhost:3306/mydb',
);
```

`port` defaults to `3306`. Leaving the path out of the connection string (or
giving just `/`) selects no database at all, which is different from a
database whose name is the empty string.

### With TLS

```dart
final db = await MySqlDatabase.connect(
  'mysql://user:password@localhost:3306/mydb?sslmode=require',
);
```

### Connection String Parameters

```
mysql://user:password@host:port/database?param=value
```

| Parameter | Description | Default |
|-----------|-------------|---------|
| `sslmode` | TLS connection mode | `prefer` |
| `sslrootcert` | CA certificate file to trust for `verify-ca` / `verify-full` | none |
| `allowPublicKeyRetrieval` | Allow `caching_sha2_password`'s full-authentication path to fetch the server's RSA public key over a connection that is not encrypted | `false` |
| `queryTimeout` | Seconds to wait for the handshake, or for any single reply, before giving up with `TimeoutException` | `30` |

See SSL/TLS below for the full set of modes, and
[Authentication](#authentication) for what `allowPublicKeyRetrieval`
protects against.

### Connection Pooling

`MySqlDatabase.connect()` opens a pool of connections. One connection is
established immediately so configuration errors fail fast; the rest are
opened on demand.

```dart
final db = await MySqlDatabase.connect(
  'mysql://user:password@localhost:3306/mydb',
  maxConnections: 20,
  acquireTimeout: Duration(seconds: 5),
);
```

| Parameter | Description | Default |
|---|---|---|
| `maxConnections` | Upper bound on open connections | `10` |
| `acquireTimeout` | How long a call waits for a free connection before throwing `PoolTimeoutException` | `30s` |
| `idleTimeout` | Idle connections unused for this long are closed. `Duration.zero` disables | `10min` |
| `maxLifetime` | Connections older than this are closed once idle. `Duration.zero` disables | `30min` |
| `validationInterval` | Idle connections unused for at least this long are pinged before reuse. `Duration.zero` pings every time | `30s` |

Each `query()` / `execute()` / `insert()` borrows a connection for the call
and returns it when done; `transaction()` pins one connection for the whole
callback.

```dart
print(db.poolStats);
```

`db.poolStats` returns a `PoolStats` snapshot.

#### What Pooling Changes

- `db.query()` / `db.execute()` called **inside** a `transaction()` callback
  run on a *different* connection and are **not** part of that transaction.
  Use the `tx` argument for everything that must be atomic -- this is also
  why a separate `SELECT LAST_INSERT_ID()` behaves the way described under
  [Execute](#execute) below.
- Session state does not survive across calls: session variables
  (`SET @x = ...`), `sql_mode`, and `TEMPORARY` tables belong to whichever
  connection ran them. Put such work inside one `transaction()` callback, or
  use `maxConnections: 1`.
- `SET autocommit = 0` sent through `execute()` does not behave the way it
  looks like it should -- see [Manual Transaction Control Is Not
  Supported](#manual-transaction-control-is-not-supported) under
  Transactions.

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

A single statement takes either `args` or `params`, never both --
combining a positional `?` with named parameters in the same statement
throws `ArgumentError`. A name used more than once in the SQL is bound once
per occurrence, from the same value in `params`; a name the SQL does not
use is simply not sent, and a name the SQL uses but `params` has no value
for throws `ArgumentError` naming it.

### Simple Query (No Parameters)

```dart
final result = await db.query('SELECT VERSION() AS v');
print(result.first['v']);
```

Each `query()` / `execute()` call runs exactly one statement. This driver
does not negotiate the server's multi-statement capability, so a
`;`-separated batch is rejected rather than run -- send each statement in
its own call, or group several atomically with `transaction()`.

## `sql_mode`

The driver reads the session's `sql_mode` once when the connection opens,
and again whenever your own SQL changes it (any `SET` statement mentioning
`sql_mode`); it never sets `sql_mode` itself. This matters because
`NO_BACKSLASH_ESCAPES` changes where a string literal ends, which changes
which `:name`-shaped sequences in a statement are placeholders rather than
text inside a string -- so the driver has to know which rule is in effect
before it can scan a statement's placeholders correctly.

## Type Mapping

`query()` returns values already converted to Dart types based on the
column's MySQL type. You never parse strings yourself.

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
| `GEOMETRY`, and any other type byte this driver does not otherwise recognize | `Uint8List` or `String`, by the same charset rule as `BLOB`/`TEXT` above -- `Uint8List` for a real `GEOMETRY` column, since it reports the binary charset |

**`TIME` comes back as a `String`, never a `DateTime`.** MySQL's `TIME` is a
signed duration from `-838:59:59` to `838:59:59`, not a time of day, and no
time-of-day type holds a value outside 24 hours.

**A zero date -- `0000-00-00`, including an otherwise-real date with a zero
month or day -- raises `MySqlDecodeException` rather than becoming `null` or
year zero.** MySQL stores that value as distinct from SQL `NULL`; mapping it
to either `null` or a real `DateTime` would lose the distinction the column
was recording, not just represent it awkwardly.

### Limitations

- **`FLOAT` loses precision beyond the usual `float32` range.** It comes
  back as a `double`, but only after being widened from a 4-byte
  `float32`, so `1.1` decodes as `1.100000023841858`, not `1.1`. Use
  `DOUBLE` or `DECIMAL` for a value that needs to round-trip exactly.
- **A JSON `null` and SQL `NULL` are indistinguishable.** `jsonDecode`
  turns a stored `null` into Dart's `null`, the same value a `NULL`
  column reports. There is no way to tell "the column has no value" from
  "the column holds the JSON value `null`" from the return of `query()`
  alone.
- **A JSON integer outside the range a double can represent exactly
  loses precision.** `JSON` decoding goes through `jsonDecode`, which
  parses a bare integer in the source text as a Dart `int` when it fits,
  but a large enough one that came from JSON's own unbounded-precision
  number syntax can still round on the way through, the same as it would
  for any other `jsonDecode` call.
- **An integer at or above 2^63 cannot be bound as a parameter.** Every
  Dart `int` parameter is sent as an 8-byte signed `BIGINT`, and a value
  that large does not fit signed 64 bits; there is no unsigned parameter
  type to fall back to.
- **`TINYINT(1)` is always read as `bool`.** A `TINYINT` column declared
  with a length of 1 is assumed to be a boolean flag, matching every
  other MySQL client's convention. There is no way to opt a `TINYINT(1)`
  column back into `int`.
- **`ANSI_QUOTES` is not tracked.** The placeholder scanner always treats
  a double-quoted run as a string literal, the default `sql_mode`'s
  reading. Under `ANSI_QUOTES`, a double-quoted run is actually a quoted
  identifier, the same case `` `...` `` already covers, and a
  placeholder-shaped sequence inside one would be misread as a
  placeholder instead of being skipped as part of the identifier.
- **Session state other than what a `SET` statement changes does not
  travel with a pooled connection.** A user variable (`SET @x := ...`)
  and a `TEMPORARY` table are both scoped to the connection that created
  them, and the pool is free to hand a later call a different one; see
  [What Pooling Changes](#what-pooling-changes) above.
- **A connection that ran any `SET` statement is discarded when
  released, not recycled.** `sql_mode` in particular is read once and
  cached per connection, so a `SET` that changed it could otherwise leave
  a stale reading behind for the next borrower. Discarding on every
  `SET`, not only ones touching `sql_mode`, keeps that one rule simple.
- **A connection with autocommit turned off is discarded the same way.**
  `SET autocommit = 0` is caught alongside every other `SET`; see
  [Manual Transaction Control Is Not
  Supported](#manual-transaction-control-is-not-supported).

### DateTime Is Always UTC

Every `DateTime` this driver returns has `isUtc == true`: the session's
`time_zone` is pinned to `+00:00` right after connecting.

### Parameters

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
`ArgumentError` naming the value's runtime type, rather than falling back to
`Object.toString()`. There is no automatic JSON encoding for a `JSON`
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

### The Auto-increment Id

MySQL has no `RETURNING`, so reading back the id an `INSERT` generated has
its own method:

```dart
final id = await db.insert(
  'INSERT INTO users (name) VALUES (:name)',
  params: {'name': 'Alice'},
);
```

**A separate `SELECT LAST_INSERT_ID()` sent through `query()` can come back
`0`, even right after a successful insert.** `LAST_INSERT_ID()` is scoped to
the connection that generated the value, and the pool is free to run that
`SELECT` on a different connection than the one that ran the `INSERT` --
nothing failed, the `SELECT` simply landed on a connection that never
inserted anything. Use `insert()` instead: it reads the id straight off the
`INSERT`'s own reply, so there is no second statement and so no second
connection for it to land on. A plain `SELECT LAST_INSERT_ID()` through
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
  // Committed if the body returns; rolled back, and the error rethrown, if
  // it throws.
});
```

### DDL Ends the Transaction Early

**MySQL commits a transaction implicitly when it runs DDL** -- `CREATE
TABLE`, for instance -- whether or not that statement itself goes on to
succeed. Running DDL inside `transaction()` raises
`MySqlTransactionEndedByDdl` naming the statement, rather than letting the
callback carry on believing a later failure could still undo it: by the
time the driver can react, MySQL has already committed.

When the DDL statement **succeeds**, everything before it -- and it -- is
known to be committed. When it **fails**, less is known: an ERR packet
carries no status flags, so all the driver can tell is that the transaction
is gone, not whether that happened through the same implicit commit or
because the server rolled the whole transaction back for some other reason.
`MySqlTransactionEndedByDdl` is raised either way, but only the success case
states a commit as fact.

The `ROLLBACK` that `db.transaction()` sends once this propagates out of the
callback still runs, but does nothing: there is no open transaction left
for it to act on.

### Manual Transaction Control Is Not Supported

Sending `START TRANSACTION` or `BEGIN` through `db.execute()` fails
outright, with errno `1295`: this driver always runs statements as prepared
statements, and MySQL refuses to prepare either one. The same is true of
`CREATE PROCEDURE`, `DROP PROCEDURE`, `LOCK TABLES` and `USE`. `COMMIT`,
`ROLLBACK` and a parameterless `SET` are not affected -- `SET` runs through
the text protocol instead of being prepared, and the other two prepare and
run normally. Always use `db.transaction()`, which pins one connection for
the whole callback, instead of sending transaction-control statements
through `execute()`.

That text-protocol exception for `SET` is itself a trap: `SET autocommit =
0` goes through unprepared and succeeds, leaving an explicit transaction
open on its connection once a following statement changes data. The pool
will not hand an unfinished transaction to some other, unrelated caller, so
it discards that connection when released instead of recycling it -- but
the statement whose own reply first reveals the open transaction still
reports success from `execute()`, and since its connection is torn down
rather than committed, MySQL rolls that work back rather than keeping it.
Use `db.transaction()` instead of managing `autocommit` by hand.

## Error Handling

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
- `MySqlTransactionEndedByDdl` -- see [DDL Ends the Transaction
  Early](#ddl-ends-the-transaction-early).
- `MySqlDecodeException` -- a column's bytes were read correctly but do not
  fit the Dart type this driver would return for them (a zero date, or a
  `BIGINT UNSIGNED` at or above 2^63).
- `MySqlProtocolException` -- the driver could not make sense of what the
  server sent. Distinct from the server refusing a statement outright.
- `UnsupportedAuthPlugin` -- thrown from `connect()` when the server asks
  for an authentication plugin this driver does not implement (currently
  just `sha256_password`); see [Authentication](#authentication).

## SSL/TLS

`sslmode` is a connection-string parameter:
`mysql://user:password@host/db?sslmode=require`. **It defaults to
`prefer`, not `disable`** -- leaving it out must not silently produce a
plaintext connection to a network database.

### SSL Modes

| Mode | Behavior |
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

**`prefer` does not fall back to plaintext if a TLS handshake it started
then fails.** It only skips TLS up front when the server's own handshake
says TLS is not offered at all; once the upgrade begins, a failure (a
timeout, a reset connection, anything short of the server saying no TLS)
still fails the connection rather than quietly continuing in plaintext.

```dart
// Require TLS
final db = await MySqlDatabase.connect(
  'mysql://user:password@host/db?sslmode=require',
);

// Verify against a trusted CA
final db = await MySqlDatabase.connect(
  'mysql://user:password@host/db?sslmode=verify-full&sslrootcert=/path/to/ca.crt',
);
```

A CA file to trust, for `verify-ca` and `verify-full`, is the
`sslrootcert` parameter.

**Giving `sslrootcert` replaces the system's trusted roots, in both
modes, rather than adding to them.** A server certificate that would
otherwise verify fine against the system's own CA bundle is refused once
`sslrootcert` is set, unless it also verifies against the CA file given.

## Authentication

Supported authentication plugins:

- **`caching_sha2_password`** -- including its public-key path: when the
  server asks for full authentication (rather than its faster cached form)
  and the connection is not encrypted, the password is RSA-encrypted with a
  public key the server provides, rather than sent in the clear.
- **`mysql_native_password`**

**`sha256_password` is not supported.** A server asking for it fails the
connection attempt with `UnsupportedAuthPlugin`, which names the plugin.

## Scope

This driver executes raw SQL through `Database` / `Transaction` only. The
ORM (`aim_orm`) and the `aim db:*` migration commands work with PostgreSQL
today; neither supports MySQL yet. Use raw SQL and manage your own schema
until that changes.

## Best Practices

### 1. Connection Management

```dart
// Connect at application startup
late MySqlDatabase db;

void main() async {
  db = await MySqlDatabase.connect(connectionString);

  // ... application logic ...

  // Close on shutdown
  await db.close();
}
```

`MySqlDatabase` is a connection pool, so a single instance shared across the
whole application is the intended usage. Do not create one per request.

### 2. Use Named Parameters

```dart
// ✅ Good - SQL injection safe
await db.query(
  'SELECT * FROM users WHERE name = :name',
  params: {'name': userInput},
);

// ❌ Bad - SQL injection risk
await db.query('SELECT * FROM users WHERE name = \'$userInput\'');
```

### 3. Use `insert()` to Read Back Generated Ids

```dart
// ✅ Good - reads the id off the INSERT's own reply
final id = await db.insert(
  'INSERT INTO users (name) VALUES (:name)',
  params: {'name': 'Alice'},
);

// ❌ Bad - can read back 0 if the SELECT lands on a different pooled
// connection than the INSERT did
await db.execute(
  'INSERT INTO users (name) VALUES (:name)',
  params: {'name': 'Alice'},
);
final rows = await db.query('SELECT LAST_INSERT_ID() AS id');
```

### 4. Handle Errors

```dart
try {
  final result = await db.query('SELECT ...');
  print(result.first);
} on MySqlException catch (e) {
  // Handle database errors
  print('Database error: ${e.message}');
} catch (e) {
  // Handle other errors
  print('Unexpected error: $e');
}
```

### 5. Use Transactions for Multiple Operations

```dart
// ✅ Good - atomic operation
await db.transaction((tx) async {
  await tx.execute('UPDATE ...');
  await tx.execute('INSERT ...');
});

// ❌ Bad - not atomic
await db.execute('UPDATE ...');
await db.execute('INSERT ...'); // If this fails, UPDATE is already committed
```

## Complete Example

```dart
import 'package:aim_mysql/aim_mysql.dart';

void main() async {
  // Connect
  final db = await MySqlDatabase.connect(
    'mysql://root:password@localhost:3306/myapp?sslmode=prefer',
  );

  try {
    // Create table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(100) NOT NULL,
        email VARCHAR(255) UNIQUE NOT NULL,
        created_at DATETIME NOT NULL
      )
    ''');

    // Insert, and read the generated id straight off the reply
    final id = await db.insert(
      'INSERT INTO users (name, email, created_at) VALUES '
      '(:name, :email, :createdAt)',
      params: {
        'name': 'Alice',
        'email': 'alice@example.com',
        'createdAt': DateTime.now().toUtc(),
      },
    );

    // Query
    final users = await db.query('SELECT * FROM users');
    for (final user in users) {
      print('${user['id']}: ${user['name']} <${user['email']}>');
    }

    // Transaction
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
