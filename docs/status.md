---
title: Component Status - Aim
description: Which parts of Aim are stable, beta, experimental, or not yet published to pub.dev. Compatibility, testing, and release policy for a pre-1.0 project.
head:
  - - meta
    - name: keywords
      content: Aim stability, Aim production ready, Aim compatibility, Aim CI, Aim release policy
---

# Component Status

Aim is pre-1.0 — every package in the workspace is at `0.4.0`, and the
project's own [CHANGELOG](https://github.com/dart-forge/aim/blob/main/CHANGELOG.md)
calls 0.4.0 a "beta". This page says, package by package, what that means in
practice: what is tested where, what has known gaps, and what to check
before relying on a given piece for production traffic.

## What the statuses mean

- **Stable** — Exercised by tests that run in CI on every push, including an
  integration test against the real backend where one exists (a live
  PostgreSQL server, a real `wrangler dev`, and so on). No known blocking
  issues. Breaking changes are announced in the [Migration Guide](/server/guides/migration).
- **Beta** — Implemented, documented, and used in the examples in this
  repository, but with a narrower test net than "Stable" — unit tests only,
  an integration suite that exists but does not run in CI by default, or a
  documented scope gap (a feature that is planned but missing).
- **Experimental** — The platform integration itself is marked experimental
  by something Aim depends on, or has not been run against a real
  deployment yet.
- **Not yet published** — In the repository and documented, but
  `publish_to: none`, so it cannot be installed from pub.dev.

## Matrix

| Component | Status | Notes |
|---|---|---|
| `aim_core` (routing, middleware, `Context`) | Stable | The largest unit-test suite in the repository; every runtime adapter depends on it |
| `aim_server` (Dart VM / `dart:io`) | Stable | The original adapter; unit-tested in CI |
| `aim_server_*` middleware (CORS, cookie, form, multipart, static, logger, SSE, JWT, basic auth) | Beta | Unit-tested through `TestClient` in CI; JWT implements HS256 only today (RS256/ES256 are planned); no dedicated security audit |
| `aim_postgres` (PostgreSQL driver) | Stable | Integration-tested against real PostgreSQL (password, MD5, and SCRAM-SHA-256 auth) in CI on every push |
| `aim_sqlite` (SQLite driver) | Not yet published | `publish_to: none`. Its test suite runs in CI, but CI only runs on `ubuntu-latest` — there is no macOS or Windows CI job, despite the driver documenting a Windows library search path |
| `aim_orm` / `aim_orm_postgres` / `aim_orm_codegen` (ORM) | Beta | Published; PostgreSQL only, no relations/eager-loading yet. `aim_orm_codegen` has an integration test that runs in CI, but its build_runner "golden" tests — the spec for the generated code — are tagged `slow` and are **not** run by CI's default job |
| `aim_cli` | Beta | Broad unit coverage, but the Docker-dependent `db:*` command tests are tagged `integration` and, unlike `aim_postgres`/`aim_orm_codegen`/`aim_workers`, CI has no step that runs them — so the CLI's migration commands are not verified against a real database on every push |
| `aim_workers` (Cloudflare Workers) | Beta | Compiles to WebAssembly; integration-tested against a real `wrangler dev` in CI |
| `aim_deno` (Supabase Edge Functions, other Deno runtimes) | Beta | Verified against a local Supabase stack, and, for HTTP routing only, against a real deployed Supabase function; cold-start time, bundle size, and every other Supabase feature beyond serving requests remain unverified, and Deno Deploy/Netlify Edge are untested entirely |
| `aim_functions` (Cloud Functions for Firebase) | Experimental | `firebase_functions`'s own Dart support is marked experimental; this adapter inherits that status |

## What CI actually runs

`.github/workflows/test.yml` runs on `ubuntu-latest` with the Dart `stable`
channel, on every push and pull request to `main`. In one job it:

1. Runs `dart analyze --fatal-warnings` over the whole workspace.
2. Runs `dart test` in every `packages/*/`, `examples/*/`, and `tools/*/`
   directory that has a test file (skipping directories with none).
3. Runs `aim_workers`'s integration suite against a real `wrangler dev`.
4. Runs `aim_postgres`'s integration suite against real PostgreSQL
   containers.
5. Runs `aim_orm_codegen`'s integration suite against real PostgreSQL.

Not covered by CI: Deno/Supabase Edge Functions, Cloud Functions for
Firebase, `aim_sqlite`'s and `aim_cli`'s Docker-dependent test tags, the
ORM codegen "golden" tests, and any platform other than Linux. Contributors
run those locally — see the commands in each package's `test/README.md` or
`dart_test.yaml` where one exists.

## Compatibility and releases

- All `aim_*` packages in the workspace share one version and are released
  together — a project that depends on more than one should keep them on
  matching versions.
- Breaking changes are called out per release in the
  [Migration Guide](/server/guides/migration) and in the root
  [CHANGELOG](https://github.com/dart-forge/aim/blob/main/CHANGELOG.md).
  Before 1.0, a breaking change can land in any release.
- Every package requires Dart SDK `^3.13.0`. The team develops against
  `3.13.3` (pinned via `mise.toml`); CI runs against whatever Dart currently
  publishes as `stable`.

## Security reporting

There is no `SECURITY.md` yet, so there is no dedicated private reporting
channel. Until one exists, the only place to report a suspected
vulnerability is the public
[GitHub issue tracker](https://github.com/dart-forge/aim/issues). Defining a
private channel is an open item for the project.

## Contributing

There is no `CONTRIBUTING.md` yet either. Open an issue or a pull request
on [GitHub](https://github.com/dart-forge/aim) to start a conversation
before sending a large change.

## Growing a project

See [Best Practices](/server/guides/best-practices#project-structure) for
the recommended layout (routes, middleware, models, services) as an
application grows past a single file.

## Benchmarks

A benchmark suite now lives in `bench/`. The first measured results, with
the machine, versions, and conditions, are on the
[Benchmarks](/benchmarks) page; they cover hello-world-class handlers over
loopback and say nothing about database-bound applications. Statements
elsewhere on this site remain limited to what the implementation shows
(linear-scan routing) and to those measured numbers.
