# aim_workers

Run an [Aim](https://pub.dev/packages/aim_core) application on Cloudflare workerd (Cloudflare Workers), compiled to WebAssembly with `dart compile wasm`.

```dart
import 'package:aim_workers/aim_workers.dart';

void main() {
  final app = Aim();
  app.get('/', (c) async => c.text('Hello from Dart on workerd'));
  app.serveWorkers();
}
```

`serveWorkers()` registers `globalThis.__aimFetch`. A small JS entry module instantiates the wasm module on the first request and forwards `fetch(request, env, ctx)` to it. See `example/main.dart` in this package for a minimal handler.

This package re-exports `aim_edge` (which itself re-exports `aim_core`), so importing `package:aim_workers/aim_workers.dart` alone is enough to build and run an app.

## Bindings and request metadata

`c.env` returns a typed `EdgeEnv?` (a `WorkersEnv` on this runtime): `c.env?.string('GREETING')` reads a var or secret, `c.env?.get('MY_KV')` returns a resource binding (KV namespace, D1 database, ...) as a raw `JSObject` you call with `dart:js_interop`, and `c.env?.has('MY_KV')` checks presence.

`c.cf` returns a typed `CfProperties?` for Cloudflare's `request.cf` metadata: `c.cf?.country`, `c.cf?.colo`, `c.cf?.city`, `c.cf?.asn`, and more.

`c.executionContext` is a raw `JSObject?`, for `waitUntil` / `passThroughOnException` via `dart:js_interop`.

## Middleware

The `aim_server_*` middleware packages (cors, cookie, form, logger, sse, jwt, basic_auth) depend on `aim_core` and work unchanged on workerd. `aim_server_static` and `aim_server_multipart`'s `saveTo()` need the file system and are VM-only.

## Limitations (v1)

- Request bodies are read fully into memory before the handler runs.
- Response bodies are streamed without backpressure; fast producers buffer in the JS queue.
- `serveWorkers()` must be called synchronously from `main()`; the JS entry module expects `globalThis.__aimFetch` to exist right after `invokeMain()`.
- Responses with status 101, 204, 205, or 304 are sent without a body regardless of the Dart body.
