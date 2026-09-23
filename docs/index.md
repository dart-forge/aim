---
layout: home
title: Aim - Modular Dart Ecosystem
titleTemplate: Server, Database, ORM - on the Dart VM, Cloudflare Workers, and Cloud Functions
description: A modular ecosystem for Dart. Web server, database, ORM, and CLI tools as independent packages. Runs on the Dart VM, on Cloudflare Workers via WebAssembly, and on Cloud Functions for Firebase.

hero:
  name: "Aim"
  text: "Modular ecosystem for Dart"
  tagline: Web server, database, ORM - on the Dart VM, Cloudflare Workers, and Cloud Functions
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
    details: Lightweight, fast web framework with Context API, routing, middleware, and authentication.
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
    details: Compile the same app to WebAssembly and run it as a Supabase Edge Function on Deno. Verified against a local Supabase stack; a production deploy is not yet verified.
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

This list is intentionally free of performance claims: there is no
benchmark suite in the repository yet.

## How mature is each piece?

Every package is pre-1.0 (`0.4.0`), and not every part of Aim has the same
level of testing. `aim_core`, `aim_server`, and `aim_postgres` are
integration-tested in CI on every push; the ORM, the CLI's database
commands, and the edge/Deno adapters have real but narrower test
coverage; Cloud Functions for Firebase is explicitly experimental. See
[Component Status](/status) for the full breakdown before deciding what to
put in front of production traffic.
