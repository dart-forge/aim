## Unreleased

### Breaking

- Query results are now typed. Values are decoded by PostgreSQL type OID:
  integers → `int`, floats → `double`, `boolean` → `bool`, `json`/`jsonb` →
  `jsonDecode` result, `bytea` → `Uint8List`, one-dimensional arrays →
  `List`. `numeric` stays `String`. Unknown types stay `String`.
  Code that did `int.parse(row['id'] as String)` must become `row['id'] as int`.
- `DateTime` values are always UTC (`isUtc == true`). `timestamp without
  time zone` is read as a UTC wall clock, matching how parameters are sent;
  previously it was read in the local zone, which shifted values on servers
  whose `TimeZone` was not UTC.
- `execute()` returns the affected row count from CommandComplete instead of
  always `0`. Multiple statements in one call are summed.
- `PostgresConnectionMessageParser.parseDataRow` returns raw `Uint8List?`
  cells instead of `String?`.

### Features

- Parameters accept `List` (PostgreSQL array literal), `Map` (JSON) and
  `Uint8List` (`bytea`), so values read from one query can be passed to the next.
- `PostgresDecodeException` (exported) is thrown when a value of a known type
  cannot be decoded (for example `'infinity'::timestamp`). The connection
  stays usable.
- `QueryResult.affectedRows`.

## 0.2.0

### Features

- Connection pooling: `PostgresDatabase.connect()` now manages a pool of connections.
  New named parameters `maxConnections` (default 10), `acquireTimeout` (30s),
  `idleTimeout` (10min), `maxLifetime` (30min) and `validationInterval` (30s).
  `PostgresDatabase.poolStats` exposes a `PoolStats` snapshot.
  `PoolTimeoutException` is thrown when no connection becomes available in time.
- Queries on a single connection are now serialized, so concurrent queries inside
  one transaction no longer corrupt the protocol stream.
- `PostgresConnection.isBroken`, `isClosed` and `ping()`.

### Fixes

- Concurrent `query()` / `execute()` calls on one `PostgresDatabase` previously
  interleaved on a single socket. They now run on separate pooled connections.

### Behaviour changes

- `db.query()` / `db.execute()` inside a `transaction()` callback now run on a
  separate pooled connection and are not part of the transaction; use `tx`.
- Session state (`TEMP` tables, `SET`, `LISTEN`, advisory locks) no longer
  persists across calls. Use `maxConnections: 1` to keep the old single-connection
  behaviour.
- A connection returned to the pool while inside a transaction (manual `BEGIN`
  via `execute()`) is discarded rather than reused.
- `acquireTimeout` bounds each blocking step of acquiring a connection
  (validation, connect, wait).


## 0.1.1

See [Release Notes](https://github.com/aim-dart/aim/releases/tag/0.1.1)


## 0.1.0

See [Release Notes](https://github.com/aim-dart/aim/releases/tag/v0.1.0)


## 0.0.1

Initial release of aim_postgres - A native PostgreSQL driver for Dart.

### Features

- PostgreSQL Wire Protocol:
  - Full implementation of PostgreSQL protocol version 3.0
  - Simple Query Protocol for static SQL
  - Extended Query Protocol for parameterized queries
  - Message parsing for all common message types

- SSL/TLS Support:
  - Multiple SSL modes: disable, allow, prefer, require, verify-ca, verify-full
  - CA certificate verification
  - Hostname verification (verify-full mode)

- Authentication:
  - Cleartext password authentication
  - MD5 password authentication
  - SCRAM-SHA-256 authentication (PostgreSQL 10+)

- Query Execution:
  - `query()` method for SELECT statements
  - `execute()` method for INSERT/UPDATE/DELETE
  - Positional parameters (`$1`, `$2`, ...)
  - Named parameters (`:name`, `:id`, ...)
  - Automatic parameter conversion (int, double, String, bool, DateTime)

- Transactions:
  - `transaction()` method with callback
  - Automatic COMMIT on success
  - Automatic ROLLBACK on error

- Notice Messages:
  - Stream-based notice/warning message handling
  - Access via `connection.noticeMessage` stream

### Supported

- Dart SDK: `^3.10.0`
- PostgreSQL: 9.5+ (SCRAM-SHA-256 requires PostgreSQL 10+)

### What's Included

- `PostgresDatabase` - High-level database API
- `PostgresConnection` - Low-level connection handling
- `PostgresTransaction` - Transaction context
- `QueryResult` - Query result container
- `QueryException` - Query error handling
- SSL mode enums and authentication type enums
