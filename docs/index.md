---
layout: home
title: Aim - Modular Dart Ecosystem
titleTemplate: Server, Database, ORM - on the Dart VM, Cloudflare Workers, Deno, and Cloud Functions
description: A modular ecosystem for Dart. Web server, database, ORM, and CLI tools as independent packages. Runs on the Dart VM, on Cloudflare Workers and Deno-based runtimes via WebAssembly, and on Cloud Functions for Firebase.

hero:
  name: "Aim"
  text: "Modular ecosystem for Dart"
  tagline: Web server, database, ORM - on the Dart VM, Cloudflare Workers, Deno, and Cloud Functions
  actions:
    - theme: brand
      text: Server
      link: /server/
    - theme: alt
      text: Database
      link: /database/
    - theme: alt
      text: CLI
      link: /cli/

features:
  - icon: 🌐
    title: Web Server
    details: Lightweight, modular web framework with Context API, routing, middleware, and authentication.
    link: /server/
    linkText: Get Started
  - icon: 🗄️
    title: Database
    details: Native PostgreSQL driver with SSL/TLS, transactions, and type-safe ORM. Works independently without web server.
    link: /database/
    linkText: Get Started
  - icon: ☁️
    title: Cloudflare Workers
    details: Compile the same app to WebAssembly and run it on Cloudflare Workers. Bindings via c.env, request metadata via c.cf.
    link: /server/workers
    linkText: Get Started
  - icon: 🟢
    title: Supabase Edge Functions
    details: Compile the same app to WebAssembly and run it as a Supabase Edge Function on Deno. Verified against a local Supabase stack and, for HTTP routing, a real deployed function; other aspects of a production deploy (cold start, bundle size, other Supabase features) are not yet verified.
    link: /server/supabase
    linkText: Get Started
  - icon: 🔥
    title: Cloud Functions
    details: Run the same app as an HTTP function on Cloud Functions for Firebase. The Firebase CLI compiles and deploys it; aim dev runs it in the emulator. Dart support is experimental.
    link: /server/functions
    linkText: Get Started
  - icon: ⚡
    title: CLI Tools
    details: Project scaffolding, hot reload, production builds, wasm builds for Cloudflare Workers, and the Firebase emulator for Cloud Functions.
    link: /cli/
    linkText: Get Started
  - icon: 🧩
    title: Modular
    details: Use what you need. Each package works independently - add only what your project requires.
  - icon: ✅
    title: Validation
    details: Declare a request's shape as a procedure and read it back with static types - no cast, no code generation.
    link: /server/validation
    linkText: Get Started
---

## Architecture

Aim separates reusable web primitives from runtime adapters. `aim_core`
holds routing, middleware, and the `Context` API; it has no dependency on
`dart:io`, WebAssembly, or any specific host. Each runtime is a thin
adapter on top of it, and `aim_workers` (Cloudflare workerd) and
`aim_deno` (Deno-based runtimes, including Supabase Edge Functions) share
a common edge layer, `aim_edge`, that application code never depends on
directly.

```text
                          Aim application
                                |
                             aim_core
                  (routing, middleware, Context)
        +-----------+-----------------+-----------------+
        |           |                 |
     dart:io    Cloud Functions      aim_edge
   aim_server    aim_functions   (shared edge plumbing)
                                  +--------+--------+
                                  |                 |
                               workerd            Deno
                             aim_workers        aim_deno
```

The practical effect: the same handlers and the same middleware packages
(`aim_server_cors`, `aim_server_jwt`, and so on) run unchanged on every
target except `aim_server_static` and file-saving in
`aim_server_multipart`, which need a filesystem and are VM-only. See
[Cloudflare Workers](/server/workers), [Supabase Edge Functions](/server/supabase),
and [Cloud Functions for Firebase](/server/functions) for what differs on
each runtime.

The database packages follow the same `dart:io` line: `aim_postgres`,
`aim_sqlite`, and the ORM (`aim_orm`/`aim_orm_postgres`) need `dart:io` and
run on `aim_server` and on `aim_functions` (a compiled native binary, not
WebAssembly). They cannot run inside a Cloudflare Worker or a Deno wasm
build — on those, use the platform's own bindings instead (Cloudflare's D1
or Hyperdrive through `c.env` on Workers, for example). See the
[Database](/database/) section and the [Workers limitations](/server/workers#limitations).

## Why Aim?

- **A small, familiar HTTP API** — `Context`-based, inspired by
  [Hono](https://hono.dev/), not a large surface to learn before writing a
  route.
- **Modular by default** — middleware, the PostgreSQL driver, and the ORM
  are separate packages; `aim_postgres`/`aim_orm` work without `aim_server`
  at all, for CLI tools, batch jobs, or migration scripts.
- **One core, several runtimes** — the same application code targets the
  Dart VM, Cloudflare Workers, Deno-based runtimes, and (experimentally)
  Cloud Functions for Firebase, with the differences documented rather
  than hidden.
- **A first-party CLI** — `aim_cli` scaffolds a project, runs a hot-reload
  dev server, builds for each target, and drives schema-diff database
  migrations.
- **Testing without a socket** — `aim_server_testing`'s `TestClient` runs
  the full request pipeline in-process.

This list is intentionally free of performance adjectives; measured
numbers, with the machine and conditions they were taken under, are on the
[Benchmarks](/benchmarks) page.

## How mature is each piece?

Every package is pre-1.0 (`0.4.0`), and not every part of Aim has the same
level of testing. `aim_core` and `aim_server` are unit-tested in CI on
every push, and `aim_postgres` is integration-tested there against a real
PostgreSQL server; the ORM, the CLI's database commands, and the edge/Deno
adapters have real but narrower test coverage; Cloud Functions for Firebase
is explicitly experimental. See
[Component Status](/status) for the full breakdown before deciding what to
put in front of production traffic.
