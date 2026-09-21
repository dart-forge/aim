# aim_deno

Run an [Aim](https://pub.dev/packages/aim_core) application on Deno-based runtimes — Supabase Edge Functions, Deno Deploy, Netlify Edge — compiled to WebAssembly with `dart compile wasm`.

```dart
import 'package:aim_deno/aim_deno.dart';

void main() {
  final app = Aim();
  app.get('/', (c) async => c.text('Hello from Dart on Deno'));
  app.serveDeno();
}
```

`serveDeno()` registers `globalThis.__aimFetch`. A small JS entry module instantiates the wasm module on the first request and forwards `fetch(request)` to it. See `example/main.dart` in this package for a minimal handler.

This package re-exports `aim_edge` (which itself re-exports `aim_core`), so importing `package:aim_deno/aim_deno.dart` alone is enough to build and run an app.

## `basePath`

Supabase Edge Functions serve each function under `/<function-name>` and pass that segment through to the handler: a request for `/users/42` arrives with a path of `/<function-name>/users/42`. An app whose routes are written as `/` and `/users/:id` answers 404 on every path unless that segment is stripped first.

```dart
app.serveDeno(basePath: 'my_api');
```

Deno Deploy and Netlify Edge serve at the root and need nothing.

## Environment variables

`c.env` returns a typed `EdgeEnv?` (a `DenoEnv` on this runtime): `c.env?.string('GREETING')` reads a Deno environment variable, and `c.env?.has('GREETING')` checks presence. Deno has no resource bindings, so `c.env?.get(name)` is always `null`.

## Middleware

The `aim_server_*` middleware packages (cors, cookie, form, logger, sse, jwt, basic_auth) depend on `aim_core` and work unchanged on Deno. `aim_server_static` and `aim_server_multipart`'s `saveTo()` need the file system and are VM-only.

## Limitations (v1)

- Request bodies are read fully into memory before the handler runs.
- Response bodies are streamed without backpressure; fast producers buffer in the JS queue.
- `serveDeno()` must be called synchronously from `main()`; the JS entry module expects `globalThis.__aimFetch` to exist right after `invokeMain()`.
- Responses with status 101, 204, 205, or 304 are sent without a body regardless of the Dart body.
