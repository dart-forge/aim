# Changelog

## 0.4.0

Fourth beta. The edge adapter is split by runtime, and Supabase Edge Functions joins the Dart VM, Cloudflare workerd and Cloud Functions for Firebase as a place an Aim application runs. **Breaking for `aim_edge`**: it is now the shared edge package, and the Cloudflare adapter moved to `aim_workers`. See the [Migration Guide](https://aim-dart.dev/server/guides/migration) for the five edits an existing Workers project needs.

### Highlights

- **`aim_deno`** (new): run an app on Deno-based runtimes. `serveDeno()`, string environment variables through `c.env`, and `basePath` for runtimes that serve a function under a path. Verified on Supabase Edge Functions both locally and against a deployed function.
- **`aim_workers`** (new): the Cloudflare workerd adapter, split out of `aim_edge` unchanged. `serveWorkers()`, resource bindings through `c.env`, `c.cf`, `c.executionContext`. Its integration suite runs the same 13 checks through `wrangler dev` as before.
- **`aim_edge`**: now the shared edge package — request and response translation, the fetch pipeline, and the `EdgeEnv` and `EdgeRaw` interfaces. Adapter authors get a second entry point, `package:aim_edge/adapter.dart`. Applications depend on `aim_workers` or `aim_deno`, not on this directly.
- **`aim_cli`**: `aim.target` gains `supabase` and renames `edge` to `workers`. `aim create --target supabase` scaffolds a Supabase project, and `aim dev` starts the local Supabase stack itself when it is not running — it never stops it, since another tool may be sharing that database. `aim build` for this target writes into `supabase/functions/<name>/`, where `static_files` can carry the wasm.
- `c.env`, `c.cf` and `c.executionContext` are called exactly as before on Cloudflare. Only the package name, `serveEdge()` → `serveWorkers()`, the target name and the wasm output path changed.

### Breaking changes

- `aim_edge` no longer serves an application. `serveEdge()`, `Bindings` and `CfProperties` moved to `aim_workers`, along with `c.cf` and `c.executionContext`. No compatibility shim is possible: `serveEdge()` needs the types that moved, and depending on `aim_workers` from `aim_edge` would be circular. A caret constraint on `^0.3.0` excludes `0.4.0`, so no project is upgraded into this without asking.
- `aim.target: edge` is rejected with an error naming both `workers` and `aim_workers`, rather than warned about. The dependency changed name too, so a warning would leave a project half-migrated.
- `aim build` for the Cloudflare target writes `build/workers/` where it wrote `build/edge/`. A project scaffolded before this release has two imports in `src/index.mjs` that name the old path.

### Packages in this release

`aim_workers` 0.4.0 (new), `aim_deno` 0.4.0 (new), and `aim_core`, `aim_edge`, `aim_server`, `aim_functions`, `aim_cli`, `aim_server_cors`, `aim_server_cookie`, `aim_server_form`, `aim_server_multipart`, `aim_server_static`, `aim_server_logger`, `aim_server_sse`, `aim_server_jwt`, `aim_server_basic_auth`, `aim_server_testing`, `aim_database`, `aim_postgres`, `aim_orm`, `aim_orm_postgres`, `aim_orm_codegen` — all 0.4.0.

`aim_sqlite` is in the repository but held back from this release.

## 0.3.0

Third beta. The same application now runs on Cloud Functions for Firebase as well as on the Dart VM and Cloudflare workerd, and `aim_cli` scaffolds, runs and deploys such a project end to end. One breaking change, to serial columns; see below.

### Highlights

- **`aim_functions`** (new): run an app as a Cloud Functions for Firebase `onRequest` HTTP function. `app.serveFunction()` returns a plain shelf handler, so the package's only runtime dependencies are `aim_core` and `shelf` — `firebase_functions` is something your own entry point needs, not the adapter. Requires `firebase_functions` 0.8.0 or later: on 0.6.x the function name is not stripped before dispatch, which leaves an app whose routes are written as `/` unreachable locally. Verified against the Firebase emulator and against a deployed function. Only `onRequest` is supported; `onCall` is Firebase's own RPC convention and does not fit an HTTP-in, HTTP-out adapter.
- **`aim_cli`**: `aim: target: functions` in `pubspec.yaml`. `aim create --target functions` scaffolds a Cloud Functions project and asks for the Firebase project id — flat, with `firebase.json` next to `pubspec.yaml`, so the CLI and the Firebase CLI agree on where the project root is. `aim dev` starts `firebase emulators:start --only functions` and adds no watcher of its own, because the emulator rebuilds Dart functions itself. `aim build` does nothing for this target: `firebase deploy` compiles on your machine and uploads the artifact.
- Dart support in Firebase is experimental, and a deploy needs the Cloud Run Admin API enabled — a Dart function is deployed as a Cloud Run service, and `firebase deploy` does not switch that API on for you.

### Breaking changes

- `aim_orm_postgres`: `SerialColumn` is `Column<int, SerialColumn>` where it was `Column<String, SerialColumn>`. `SERIAL` stores a 4-byte integer, the code generator already maps it to `int`, and the class's own documentation said so — only the type parameter disagreed, which made every comparison on a serial key take a string. Three things follow for anyone who had written code against the old type: comparisons such as `users.id.eq('1')` become `users.id.eq(1)`; a foreign key pointing at a serial column has to have the same value type, so `varchar('user_id').references(() => users.id)` becomes `integer('user_id').references(() => users.id)`; and `defaultValue`, along with `copyWith`'s `defaultValue` parameter, is `int?` where it was `String?`.
- `aim_orm_postgres`: asking a serial column for a default now throws `UnsupportedError` instead of being ignored. `SERIAL` already means `integer NOT NULL DEFAULT nextval(...)`, and PostgreSQL answers a second default with "multiple default values specified for column". `aim db:generate` refuses the same thing when it reads the schema, because it reads the source rather than running it.

### Packages in this release

`aim_functions` 0.3.0 (new), and `aim_core`, `aim_server`, `aim_edge`, `aim_cli`, `aim_server_cors`, `aim_server_cookie`, `aim_server_form`, `aim_server_multipart`, `aim_server_static`, `aim_server_logger`, `aim_server_sse`, `aim_server_jwt`, `aim_server_basic_auth`, `aim_server_testing`, `aim_database`, `aim_postgres`, `aim_orm`, `aim_orm_postgres`, `aim_orm_codegen` — all 0.3.0.

`aim_sqlite` is in the repository but held back from this release.

## 0.2.0

Second beta. Aim now runs on Cloudflare workerd as well as the Dart VM, `aim_postgres` pools connections, and the per-request variable type follows Hono's naming. This release contains breaking changes; see the [Migration Guide](https://aim-dart.dev/server/guides/migration) for step-by-step instructions.

### Highlights

- **`aim_core`** (new): the framework core (`Aim`, routing, middleware, `Context`, `Request`, `Response`) with no `dart:io` dependency. `aim_server` re-exports it, so existing imports keep working.
- **`aim_edge`** (new): run the same app on Cloudflare workerd, compiled with `dart compile wasm`. `app.serveEdge()`, `c.env` (`Bindings`), `c.cf` (`CfProperties`), `c.executionContext`. Streaming responses (SSE) work.
- **`aim_cli`**: `aim: target: edge` in `pubspec.yaml` switches `aim build` to WebAssembly and `aim dev` to `wrangler dev` with recompilation on change. `aim create --target edge` scaffolds a worker project.
- **`aim_postgres`**: connection pooling in `PostgresDatabase.connect()` (`maxConnections`, `acquireTimeout`, `idleTimeout`, `maxLifetime`, `validationInterval`, `poolStats`). Queries on one connection are serialized, fixing protocol corruption under concurrent requests.
- Requires Dart 3.13.

### Breaking changes

- `Env` → `Variables`, `EmptyEnv` → `EmptyVariables`; `Aim(envFactory:)` → `Aim(variablesFactory:)`. `JwtEnv` → `JwtVariables`, `BasicAuthEnv` → `BasicAuthVariables`. Deprecated typedefs for the class names remain for this release; `envFactory` has no alias.
- `Request.raw` is `Object?`. On the VM use `c.req.httpRequest` (extension from `aim_server`).
- `aim_server_multipart`: `UploadedFile.saveTo()` moved to `package:aim_server_multipart/aim_server_multipart_io.dart`. The main library now exports the public API (`MultipartFormData`, `UploadedFile`, `parseMultipart`, `MultipartRequest`); `src/` imports should be replaced.
- `aim_cli`: `--entry` now overrides `aim.entry` for `aim dev` too; `aim.env` values are parsed as YAML (quote values containing `:`); errors exit non-zero.
- `aim_postgres`: `db.query()` / `db.execute()` inside a `transaction()` callback now run on a separate pooled connection. Use `tx` for statements that belong to the transaction. Session state (`SET`, `TEMP` tables, `LISTEN`, advisory locks) no longer persists across calls; pass `maxConnections: 1` to keep single-connection behaviour.
- `aim_orm_codegen` and `aim_cli` require `analyzer ^14.0.0`; the code generator works with `source_gen ^4.3.0` and `build_runner 2.16`.

### Other changes

- Middleware packages (`aim_server_cors`, `cookie`, `form`, `logger`, `sse`, `jwt`, `basic_auth`, `multipart`) depend on `aim_core` and run unchanged on both runtimes. `aim_server_static` remains VM-only.
- `aim_server`: `Aim.handle()` no longer prints unhandled errors; `serve()` still logs them.
- `aim_postgres`: `PostgresConnection.isBroken`, `isClosed`, `ping()`; `PoolTimeoutException`.
- `aim_cli`: `aim:` configuration is parsed with `package:yaml`; the release tooling keeps the scaffold templates' dependency pins in sync.
- Docs: new Migration Guide, CLI `target` documentation, connection pooling guide.

### Packages in this release

`aim_core` 0.2.0 (new), `aim_server`, `aim_edge` 0.2.0 (new), `aim_cli`, `aim_server_cors`, `aim_server_cookie`, `aim_server_form`, `aim_server_multipart`, `aim_server_static`, `aim_server_logger`, `aim_server_sse`, `aim_server_jwt`, `aim_server_basic_auth`, `aim_server_testing`, `aim_database`, `aim_postgres`, `aim_orm`, `aim_orm_postgres`, `aim_orm_codegen` — all 0.2.0.

## Unreleased

### Database (aim_postgres)

- Connection pooling in `PostgresDatabase.connect()`: `maxConnections` (default 10),
  `acquireTimeout` (30s), `idleTimeout` (10min), `maxLifetime` (30min),
  `validationInterval` (30s), plus `PostgresDatabase.poolStats` and
  `PoolTimeoutException`.
- Queries on one connection are serialized, and `PostgresConnection` gained
  `isBroken`, `isClosed` and `ping()`.
- Fixed: concurrent `query()` / `execute()` calls no longer interleave on a
  single socket.
- Behaviour change: `db.query()` / `db.execute()` inside a `transaction()`
  callback run on a separate connection and are not part of the transaction;
  use `tx`.
- Behaviour change: session state (`TEMP` tables, `SET`, `LISTEN`, advisory
  locks) no longer persists across calls; use `maxConnections: 1` for the old
  single-connection behaviour.
- Behaviour change: a connection returned while inside a transaction (manual
  `BEGIN`) is discarded, and `acquireTimeout` now bounds each blocking step of
  acquiring a connection.


## 0.1.1
Internal fixes. No functional changes.

## 0.1.0

First beta release of Aim Framework - a modular ecosystem for Dart.

### Highlights

- Lightweight, fast web server framework
- Native PostgreSQL driver (no external dependencies)
- Type-safe ORM with Record syntax
- CLI tools with hot reload and database migrations

### Web Server (aim_server)

- HTTP server built on Dart's native `HttpServer`
- Path-based routing with parameter support (`/users/:id`)
- Composable middleware chain
- JSON, text, HTML response handling
- Real-time SSE streaming support
- Custom error handlers (404, global)

### Middleware Packages

- **aim_server_cors**: CORS configuration
- **aim_server_cookie**: Secure cookie management
- **aim_server_form**: Form data parsing
- **aim_server_multipart**: File upload handling
- **aim_server_static**: Static file serving
- **aim_server_logger**: HTTP request logging
- **aim_server_sse**: Server-Sent Events
- **aim_server_jwt**: JWT authentication
- **aim_server_basic_auth**: Basic authentication

### Testing (aim_server_testing)

- Test helpers and matchers
- Mock objects for unit testing
- Integration test utilities

### Database (aim_database + aim_postgres)

- Database abstraction layer
- Native PostgreSQL Wire Protocol implementation
- SSL/TLS support (disable, allow, prefer, require, verify-ca, verify-full)
- Authentication: cleartext, MD5, SCRAM-SHA-256
- Named parameters (`:name`) and positional parameters (`$1`)
- Transaction support with automatic commit/rollback

### ORM (aim_orm + aim_orm_postgres + aim_orm_codegen)

- Type-safe table definitions using Dart Record syntax
- Column types: `integer`, `bigint`, `varchar`, `text`, `boolean`, `timestamp`, `uuid`, `json`
- Column modifiers: `primaryKey`, `unique`, `nullable`, `withDefault`, `indexed`
- Query builders: SELECT, INSERT, UPDATE, DELETE
- Condition operators: `eq`, `gt`, `lt`, `gte`, `lte`, `inList`
- Code generation with `build_runner`

### CLI (aim_cli)

- `aim create <name>`: Project scaffolding
- `aim dev`: Development server with hot reload
- `aim build`: Production build with native compilation
- `aim db:generate`: Migration SQL generation from schema diff
- `aim db:migrate`: Apply pending migrations
- `aim db:rollback`: Rollback migrations
- `aim db:status`: Show migration status

### Known Limitations

- ORM Relations (1:1, 1:N, N:N) not yet supported
- SQLite driver not yet available
- `db:reset` command not yet implemented

### Requirements

- Dart SDK: `^3.10.0`
- PostgreSQL: 9.5+ (SCRAM-SHA-256 requires 10+)
