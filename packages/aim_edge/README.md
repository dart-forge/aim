# aim_edge

Shared plumbing for running an [Aim](https://pub.dev/packages/aim_core) application on an edge runtime: the translation between the platform's `Request`/`Response` and Aim's `Request`/`Response`, the `EdgeEnv` interface for runtime bindings, and the `c.env` context getter.

This package is not an adapter by itself and has no `serve*()` method. Application authors depend on one of the runtime adapters built on it instead:

- [`aim_workers`](https://pub.dev/packages/aim_workers) for Cloudflare workerd (Cloudflare Workers)
- [`aim_deno`](https://pub.dev/packages/aim_deno) for Deno-based runtimes (Supabase Edge Functions, Deno Deploy, Netlify Edge)

Both re-export `aim_edge`, so an application only needs to depend on the adapter it targets.

## Two entry points

- `package:aim_edge/aim_edge.dart` — for application code. Re-exports `aim_core` plus `EdgeEnv` and the `c.env` getter.
- `package:aim_edge/adapter.dart` — for adapter authors. Exposes `EdgeRaw`, `handleEdgeFetch`, `toAimRequest`, and `toWebResponse`, the pieces a new adapter needs to translate its runtime's `fetch` handler into an `Aim` request.

## Writing a new adapter

An adapter package implements `EdgeRaw` for its runtime (wrapping the platform's `Request` and exposing an `EdgeEnv`), then registers `globalThis.__aimFetch` by calling `handleEdgeFetch(app, EdgeRawImpl(request))` from a `serve*()` extension on `Aim`. See `aim_workers`' and `aim_deno`'s `lib/src/` for worked examples.

## Limitations (v1)

- Request bodies are read fully into memory before the handler runs.
- Response bodies are streamed without backpressure; fast producers buffer in the JS queue.
- Responses with status 101, 204, 205, or 304 are sent without a body regardless of the Dart body.
