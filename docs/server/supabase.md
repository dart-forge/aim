---
title: Supabase Edge Functions - Aim Framework
description: Run an Aim application as a Supabase Edge Function. Compile Dart to WebAssembly with aim build, develop with supabase functions serve, read environment variables with c.env.
head:
  - - meta
    - name: keywords
      content: Dart Supabase, Supabase Edge Functions, Dart WebAssembly, dart compile wasm, Deno, aim_deno, supabase functions serve
---

# Supabase Edge Functions

An Aim application is not tied to the Dart VM. The routing, middleware, and `Context` API live in `aim_core`, and a runtime adapter connects them to a platform. `aim_server` is the adapter for `dart:io`; `aim_deno` is the adapter for Deno-based runtimes, built on the shared `aim_edge` package. `dart compile wasm` output runs unmodified on Deno and on `supabase/edge-runtime` — both expose `wasmGC` and `simd`.

```dart
import 'package:aim_deno/aim_deno.dart';

void main() {
  final app = Aim();
  app.get('/', (c) async => c.text('Hello from Dart on Supabase Edge Functions'));
  app.get('/users/:id', (c) async => c.json({'id': c.param('id')}));
  app.serveDeno(basePath: 'my_api');
}
```

## Prerequisites

- Dart 3.13 or later (`dart compile wasm`).
- The [Supabase CLI](https://supabase.com/docs/guides/cli), 2.7.0 or later.
- Docker running.
- The local stack up: `supabase start`. `supabase functions serve` exits immediately without it.

## Create a project

```bash
dart install aim_cli
aim create my_api --target supabase
cd my_api
dart pub get
```

The generated project:

| File | Role |
|---|---|
| `lib/main.dart` | Your application. Ends with `app.serveDeno(basePath: 'my_api')`. |
| `supabase/functions/my_api/index.ts` | The function's Deno entry. Instantiates the wasm module on the first request and forwards every `fetch` to the Dart app. You rarely need to edit it. |
| `supabase/config.toml` | `project_id` plus a `[functions.my_api] static_files` declaration, so `main.wasm` is deployed alongside `index.ts`. |
| `pubspec.yaml` | Depends on `aim_deno` and sets `aim: target: supabase`, which switches `aim build` and `aim dev` to the Deno/wasm toolchain. |

## Routes and the function name

Supabase serves each function under `/<function-name>` and passes that segment through to the handler. Measured against a running local stack, a request for `/users/42` on a function named `my_api` arrived at the handler as `/my_api/users/42`. An app whose routes are written as `/` and `/users/:id` answered 404 on every path until that segment was removed.

```dart
app.serveDeno(basePath: 'my_api');
```

With `basePath` set, the same measurement gave `/` → 200, `/users/42` → 200 with `id` bound, an unknown path → the app's own 404 handler, and a `POST` with a JSON body → 200.

An alternative is to mount the whole app under a prefix with `app.route('my_api', subApp)` instead of stripping it in `serveDeno`. Avoid this if the same routes also need to run on `aim_workers` (Cloudflare Workers): Cloudflare does not add a function-name segment, so a route tree written for one target answers 404 on the other. `serveDeno(basePath:)` keeps the route tree itself identical between targets.

## Run it locally

```bash
aim dev
```

This starts `supabase functions serve my_api --no-verify-jwt`. It requires `supabase start` to already be running — `aim dev` does not start it for you, and fails with a reminder if the stack is down. The function's port comes from `supabase/config.toml`; `aim dev --port` is rejected for this target.

The function answers on `http://localhost:54321/functions/v1/my_api/...` — the default `supabase/config.toml` API port, `/functions/v1/`, then the function name from [Routes and the function name](#routes-and-the-function-name) above.

Changes under `lib/` trigger a recompile to `supabase/functions/my_api/main.wasm`. Unlike the Cloudflare Workers runner, `aim dev` never restarts `supabase functions serve` after a rebuild — measured against a running stack, `supabase functions serve` picks up the rebuilt `main.wasm` on its own.

## Deploy

```bash
aim build                            # supabase/functions/my_api/main.wasm + main.mjs
supabase functions deploy my_api
```

Deploy with the CLI, not `--use-api`: `--use-api` skips the bundling step that places `main.wasm` next to the deployed `index.ts`, which is what `static_files` in `supabase/config.toml` depends on.

## Environment variables

`c.env` returns a typed `EdgeEnv?` (a `DenoEnv` on this runtime): `c.env?.string('NAME')` reads a Deno environment variable, and `c.env?.has('NAME')` checks presence. Supabase has no resource bindings, so `c.env?.get(name)` is always `null`.

`aim.env` in `pubspec.yaml` does not reach a Supabase function: measured against a running local stack, a route returning `c.env?.string('AIM_PROBE')` answered `MISSING` with `AIM_PROBE` set under `aim.env`. `aim dev` prints a warning that it is ignored for `target: supabase`. Supabase takes environment variables from its own configuration instead:

- Locally, from `supabase/functions/.env` and per-function `.env` files. `supabase functions serve --env-file <path>` overrides both.
- For a deployed function, from `supabase secrets set`.

## Limitations

- A real deploy to Supabase has not been verified — only the local stack (`supabase start` + `supabase functions serve`).
- Deno Deploy and Netlify Edge, the other Deno-based runtimes `aim_deno` targets, have not been verified.

## Next Steps

- [CLI configuration](/cli/configuration#target) - `aim: target: supabase`, entry points, and how `aim dev` / `aim build` behave
- [Context](/server/concepts/context) - `c.variables`, `c.env`, and the response helpers
- [Middleware](/server/middleware/) - Packages that run on both runtimes
- [Cloudflare Workers](/server/workers) - the same app on workerd instead of Deno
- [Supabase Edge Functions documentation](https://supabase.com/docs/guides/functions) - deployment, secrets, and the local development stack
