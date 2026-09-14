---
title: PostgreSQL Driver - Aim Database
description: Native PostgreSQL driver for Dart. SSL/TLS, SCRAM-SHA-256 authentication, named parameters, and transactions.
head:
  - - meta
    - name: keywords
      content: Dart PostgreSQL, aim_postgres, PostgreSQL driver, SCRAM-SHA-256, SSL Dart
---

# PostgreSQL

Native PostgreSQL driver for Dart. Implements the PostgreSQL Wire Protocol without external dependencies.

## Features

- Native PostgreSQL Wire Protocol implementation
- SSL/TLS connection support
- Authentication methods: cleartext, MD5, SCRAM-SHA-256
- Simple Query Protocol and Extended Query Protocol
- Named parameters (`:name`) and positional parameters (`$1`)
- Transaction support

## Installation

```bash
dart pub add aim_postgres
```

## Connection

### Basic Connection

```dart
import 'package:aim_postgres/aim_postgres.dart';

final db = await PostgresDatabase.connect(
  'postgresql://user:pass@localhost:5432/mydb',
);
```

### With SSL

```dart
final db = await PostgresDatabase.connect(
  'postgresql://user:pass@localhost:5432/mydb?sslmode=require',
);
```

### Connection String Parameters

```
postgresql://user:password@host:port/database?param=value
```

| Parameter | Description | Default |
|-----------|-------------|---------|
| `sslmode` | SSL connection mode | `prefer` |

### Connection Pooling

`PostgresDatabase.connect()` opens a pool of connections. One connection is
established immediately so configuration errors fail fast; the rest are opened
on demand.

```dart
final db = await PostgresDatabase.connect(
  'postgresql://user:pass@localhost:5432/mydb',
  maxConnections: 20,
  acquireTimeout: Duration(seconds: 5),
);
```

| Parameter | Description | Default |
|-----------|-------------|---------|
| `maxConnections` | Upper bound on open connections | `10` |
| `acquireTimeout` | Bound for each blocking step of acquiring a connection (validate / connect / wait); throws `PoolTimeoutException` | `30s` |
| `idleTimeout` | Idle connections unused for this long are closed. `Duration.zero` disables | `10min` |
| `maxLifetime` | Connections older than this are closed once idle. `Duration.zero` disables | `30min` |
| `validationInterval` | Idle connections unused for at least this long are pinged before reuse. `Duration.zero` pings every time | `30s` |

Each `query()` / `execute()` borrows a connection for the duration of the call.
`transaction()` pins one connection for the whole callback. Connections that
hit a transport error are discarded and replaced automatically.

Queries issued on one connection are serialized, so concurrent calls inside a
single `transaction()` callback do not corrupt the protocol stream. That is not
transaction isolation: they still run in the same server-side transaction, in
the order they were issued.

#### What pooling changes

- `db.query()` / `db.execute()` called **inside** a `transaction()` callback run
  on a *different* connection and are **not** part of that transaction. Use the
  `tx` argument for everything that must be atomic.
- Session state does not survive across calls: `TEMP` tables, `SET`, session
  advisory locks and `LISTEN` belong to whichever connection ran them. Put such
  work inside one `transaction()` callback, or use `maxConnections: 1`.
- Nesting a `db.*` call inside a `transaction()` callback holds two connections
  at once. With `maxConnections: 1` it always ends in `PoolTimeoutException`.

```dart
print(db.poolStats);
// PoolStats(total: 3, idle: 2, inUse: 1, waiting: 0, created: 3, destroyed: 0, timeouts: 0, validationFailures: 0)
```

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
final users = await db.query(
  r'SELECT * FROM users WHERE id = $1',
  args: [123],
);
```

### Simple Query (no parameters)

```dart
final result = await db.query('SELECT version()');
print(result.first['version']);
```

When a single `query()` call runs several `;`-separated statements, the rows
of the last row-returning statement are returned; use `execute()` for the
summed row count.

## Type Mapping

`query()` returns values already converted to Dart types based on the
column's PostgreSQL type. You never parse strings yourself.

| PostgreSQL | Dart |
|---|---|
| `smallint`, `integer`, `bigint`, `oid` | `int` |
| `real`, `double precision` | `double` (`NaN`, `Infinity` preserved) |
| `numeric`, `decimal` | `String` — arbitrary precision is not representable as `double`; parse it with your decimal library of choice |
| `boolean` | `bool` |
| `text`, `varchar`, `char`, `name`, `uuid` | `String` |
| `timestamp`, `timestamptz`, `date` | `DateTime` in **UTC** (see below) |
| `time`, `timetz`, `interval` | `String` |
| `json`, `jsonb` | result of `jsonDecode` (`Map`, `List`, scalar, or `null`) |
| `bytea` | `Uint8List` |
| one-dimensional arrays of the above | `List<T?>` |
| anything else (enums, ranges, nested arrays, ...) | `String` |

### DateTime is always UTC

Every `DateTime` the driver returns has `isUtc == true`.

- `timestamp without time zone` is read as a UTC wall clock. Parameters are
  sent in UTC too, so a `DateTime` round-trips to the same instant no matter
  what the server's `TimeZone` setting is. Call `.toLocal()` when you need
  local time.
- `timestamptz` is normalized to UTC.
- `date` becomes midnight UTC.

`'infinity'::timestamp` cannot be represented as `DateTime` and raises a
`PostgresDecodeException`.

### Parameters

Parameters accept the same types the driver returns, so a value read from
one query can be passed to the next:

| Dart | Sent as |
|---|---|
| `int`, `double`, `String` | as is |
| `bool` | `t` / `f` |
| `DateTime` | ISO 8601 in UTC |
| `Uint8List` | `bytea` hex (`\x...`) |
| `Map` | JSON |
| `List` | PostgreSQL array literal (`{1,"a",NULL}`) |

A Dart `List` is sent as a PostgreSQL **array**. To send a JSON array to a
`json` / `jsonb` column, pass `jsonEncode(list)` as a `String`.

```dart
await db.execute(
  r'INSERT INTO posts (tags, meta, cover) VALUES ($1, $2, $3)',
  args: [
    ['dart', 'postgres'],          // text[]
    {'draft': true},               // jsonb
    Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]), // bytea
  ],
);
```

### Decode errors

When a value of a known type cannot be decoded, the query fails with a
`PostgresDecodeException` naming the column, the type OID and the raw text.
The connection stays usable. Unknown types are not an error; they are
returned as `String`.

## Execute

Use `execute` for `INSERT`, `UPDATE`, `DELETE`. It returns the number of
affected rows:

```dart
final inserted = await db.execute(
  'INSERT INTO users (name, email) VALUES (:name, :email)',
  params: {'name': 'Alice', 'email': 'alice@example.com'},
); // 1

final updated = await db.execute(
  'UPDATE users SET name = :name WHERE id = :id',
  params: {'name': 'Bob', 'id': 1},
); // 1

final deleted = await db.execute(
  'DELETE FROM users WHERE id = :id',
  params: {'id': 1},
); // 1 or 0
```

Statements that report no row count (DDL, `SET`, ...) return 0. When one
`execute` call runs several `;`-separated statements, the counts are summed.
Use `query()` with `RETURNING` when you need the rows themselves.

## Transactions

```dart
await db.transaction((tx) async {
  // All queries in this block are part of the transaction
  await tx.execute(
    'UPDATE accounts SET balance = balance - :amount WHERE id = :from',
    params: {'amount': 100, 'from': 1},
  );

  await tx.execute(
    'UPDATE accounts SET balance = balance + :amount WHERE id = :to',
    params: {'amount': 100, 'to': 2},
  );

  // Transaction is automatically committed if no exception is thrown
  // If an exception is thrown, the transaction is rolled back
});
```

### Manual Transaction Control Is Not Supported

Do not send `BEGIN` / `COMMIT` / `ROLLBACK` through `db.execute()`. Every
`query()` / `execute()` call borrows its own connection from the pool, so the
statements would run on different connections and nothing would be atomic.
Always use `db.transaction()`, which pins one connection for the whole callback.

If a connection is handed back to the pool while still inside a transaction
(for example after a manual `BEGIN`), the pool discards it instead of reusing
it, so the mistake costs a connection rather than corrupting later queries.

## Error Handling

```dart
try {
  await db.query('SELECT * FROM nonexistent_table');
} on QueryException catch (e) {
  print('PostgreSQL error: ${e.message}');
}
```

## SSL/TLS

### SSL Modes

| Mode | Description |
|------|-------------|
| `disable` | No SSL |
| `allow` | Try non-SSL first, then SSL |
| `prefer` | Try SSL first, then non-SSL (default) |
| `require` | SSL required |
| `verify-ca` | SSL + CA certificate verification |
| `verify-full` | SSL + CA certificate + hostname verification |

```dart
// Require SSL
final db = await PostgresDatabase.connect(
  'postgresql://user:pass@host/db?sslmode=require',
);

// Verify CA certificate
final db = await PostgresDatabase.connect(
  'postgresql://user:pass@host/db?sslmode=verify-ca',
);
```

## Authentication

Supported authentication methods:

- **Cleartext** - Sends password in plain text (use with SSL recommended)
- **MD5** - MD5 hash authentication
- **SCRAM-SHA-256** - Modern secure authentication method

Authentication method is determined by the server's `pg_hba.conf` configuration.

## Best Practices

### 1. Connection Management

```dart
// Connect at application startup
late PostgresDatabase db;

void main() async {
  db = await PostgresDatabase.connect(connectionString);

  // ... application logic ...

  // Close on shutdown
  await db.close();
}
```

`PostgresDatabase` is a connection pool, so a single instance shared across the
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

### 3. Handle Errors

```dart
try {
  final result = await db.query('SELECT ...');
} on QueryException catch (e) {
  // Handle database errors
  print('Database error: ${e.message}');
} catch (e) {
  // Handle other errors
  print('Unexpected error: $e');
}
```

### 4. Use Transactions for Multiple Operations

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
import 'package:aim_postgres/aim_postgres.dart';

void main() async {
  // Connect
  final db = await PostgresDatabase.connect(
    'postgresql://postgres:password@localhost:5432/myapp?sslmode=prefer',
  );

  try {
    // Create table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        name VARCHAR(100) NOT NULL,
        email VARCHAR(255) UNIQUE NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Insert
    await db.execute(
      'INSERT INTO users (name, email) VALUES (:name, :email)',
      params: {'name': 'Alice', 'email': 'alice@example.com'},
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
        params: {'name': 'Alice Updated', 'id': 1},
      );
    });

  } finally {
    await db.close();
  }
}
```

## Next Steps

- [ORM](/database/orm/) - Type-safe ORM (Coming Soon)
- [Database Overview](/database/) - All database packages
