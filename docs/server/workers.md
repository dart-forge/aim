---
title: Cloudflare Workers - Aim Framework
description: Run the same Aim application on Cloudflare Workers. Compile Dart to WebAssembly with aim build, develop with wrangler dev, read bindings with c.env.
head:
  - - meta
    - name: keywords
      content: Dart Cloudflare Workers, Dart WebAssembly, dart compile wasm, workerd, edge functions, aim_edge, wrangler
---

# Cloudflare Workers

An Aim application is not tied to the Dart VM. The routing, middleware, and `Context` API live in `aim_core`, and a runtime adapter connects them to a platform. `aim_server` is the adapter for `dart:io`; `aim_edge` is the adapter for Cloudflare workerd. The same handlers, the same middleware packages, compiled with `dart compile wasm` and deployed with wrangler.

```dart
import 'package:aim_edge/aim_edge.dart';

void main() {
  final app = Aim();
  app.get('/', (c) async => c.text('Hello from Dart on Cloudflare Workers'));
  app.serveEdge();
}
```

## Prerequisites

- Dart 3.13 or later (`dart compile wasm`).
- Node.js 20 or later. The CLI runs `npx wrangler@4`, which is downloaded on first use.
- A Cloudflare account for deploying. Local development with `wrangler dev` works without one.

## Create a project

```bash
dart install aim_cli
aim create my_worker --target edge
cd my_worker
dart pub get
aim dev
```

`aim dev` compiles `lib/main.dart` to WebAssembly, starts `wrangler dev` on `http://localhost:8787`, and recompiles whenever a file under `lib/` changes. wrangler reloads the worker by itself.

The generated project:

| File | Role |
|---|---|
| `lib/main.dart` | Your application. Ends with `app.serveEdge()`. |
| `src/index.mjs` | The worker's JS entry. Instantiates the wasm module on the first request and forwards every `fetch` to the Dart app. You rarely need to edit it. |
| `wrangler.jsonc` | wrangler configuration: worker name, entry, `vars`, bindings. |
| `pubspec.yaml` | Depends on `aim_edge` and sets `aim: target: edge`, which switches `aim build` and `aim dev` to the workerd toolchain. |

The worker name in `wrangler.jsonc` is the project name with underscores replaced by hyphens, because Cloudflare does not allow underscores.

## Bindings and request metadata

Values declared in `wrangler.jsonc` (`vars`, secrets, KV, D1, R2, Durable Objects, service bindings) are exposed on the context as `c.env`:

```dart
app.get('/hello', (c) async {
  final greeting = c.env?.string('GREETING') ?? 'hello'; // vars and secrets
  return c.text(greeting);
});

app.get('/kv', (c) async {
  final kv = c.env?.get('MY_KV'); // JSObject? for KV, D1, R2, ...
  // call it with dart:js_interop
  return c.text(kv == null ? 'no binding' : 'bound');
});
```

`c.env` is `null` when the app runs on the Dart VM, so the same handler can fall back gracefully.

Cloudflare's request metadata (`request.cf`) is available as `c.cf`:

```dart
app.get('/where', (c) async {
  final cf = c.cf;
  return c.json({
    'country': cf?.country,   // 'JP'
    'colo': cf?.colo,         // 'NRT'
    'city': cf?.city,
    'timezone': cf?.timezone,
  });
});
```

Typed getters cover `country`, `colo`, `city`, `region`, `regionCode`, `continent`, `timezone`, `postalCode`, `latitude`, `longitude`, `asn`, `asOrganization`, `httpProtocol`, `tlsVersion`, and `tlsCipher`. Anything else is reachable with `cf.string('name')` or `cf.raw`.

The worker's `ExecutionContext` (for `waitUntil`) is `c.executionContext`, a `JSObject?` you drive with `dart:js_interop`.

::: tip Variables vs. env
`Variables` (`c.variables`) are per-request values your middleware sets. `c.env` holds the worker's bindings, fixed for the lifetime of the worker. See [Context](/server/concepts/context#variables).
:::

## Middleware

Middleware packages depend on `aim_core`, not on `dart:io`, so they work unchanged on Workers: `aim_server_cors`, `aim_server_cookie`, `aim_server_form`, `aim_server_multipart` (parsing), `aim_server_logger`, `aim_server_sse`, `aim_server_jwt`, and `aim_server_basic_auth`.

Two things need the file system and stay on the Dart VM: `aim_server_static`, and `UploadedFile.saveTo()` from `aim_server_multipart_io.dart`.

Server-Sent Events stream on Workers as they do on the VM; the response body is passed to the runtime as a `ReadableStream`.

## Deploy

```bash
aim build                 # dart compile wasm -> build/edge/main.wasm + main.mjs
npx wrangler@4 deploy
```

`aim build` writes the wasm module and its loader to `build/edge/`, which `src/index.mjs` imports. Everything else is standard wrangler: `wrangler.jsonc` decides the name, routes, and bindings, and `wrangler secret put` stores secrets.

## Running one app on both runtimes

Keep the app in a function that takes an `Aim` and register routes there. Then use two entry points:

```dart
// lib/app.dart
import 'package:aim_core/aim_core.dart';

void configure(Aim app) {
  app.get('/', (c) async => c.text('Hello'));
}
```

```dart
// bin/server.dart  (Dart VM)
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:my_app/app.dart';

void main() async {
  final app = Aim();
  configure(app);
  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
}
```

```dart
// lib/main.dart  (Cloudflare Workers)
import 'package:aim_edge/aim_edge.dart';
import 'package:my_app/app.dart';

void main() {
  final app = Aim();
  configure(app);
  app.serveEdge();
}
```

Only the entry files differ. `aim build` and `aim dev` follow `aim: target:` in `pubspec.yaml` (`server` by default, `edge` for Workers), so set it to the runtime you deploy with the CLI. The other entry still works with plain Dart tooling: `dart run bin/server.dart` or `dart compile exe bin/server.dart` for the VM, `dart compile wasm lib/main.dart` for Workers.

## Limitations

- Request bodies are read fully into memory before the handler runs.
- Response streaming has no backpressure; a fast producer buffers in the runtime.
- `serveEdge()` must be called synchronously from `main()`.
- Responses with status 101, 204, 205, or 304 are sent without a body, as the Fetch specification requires.
- Everything that needs `dart:io` (files, sockets, processes) is unavailable in the worker. `aim_postgres` therefore cannot be used from a worker; use Cloudflare's D1 or Hyperdrive bindings through `c.env` instead.

## Next Steps

- [CLI configuration](/cli/configuration#target) - `aim: target: edge`, entry points, and how `aim dev` / `aim build` behave
- [Context](/server/concepts/context) - `c.variables`, `c.env`, and the response helpers
- [Middleware](/server/middleware/) - Packages that run on both runtimes
- [Cloudflare Workers documentation](https://developers.cloudflare.com/workers/) - bindings, routes, and wrangler
