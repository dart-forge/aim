## 0.4.0

- **Breaking:** `aim_edge` no longer runs applications by itself. It now holds
  only the plumbing shared by every edge runtime (`EdgeContext`, `EdgeEnv`,
  and the adapter-author surface in `adapter.dart`); Cloudflare-specific code
  moved to the new `aim_workers` package.
- **Breaking:** `serveEdge()` is removed. Cloudflare Workers applications call
  `serveWorkers()` from `aim_workers` instead.
- **Breaking:** `Bindings`, `CfProperties`, `c.cf`, and `c.executionContext`
  are removed from `aim_edge`. They now live in `aim_workers`, unchanged.
- New `aim_deno` package: a Deno adapter for Supabase Edge Functions, Deno
  Deploy, and Netlify Edge, built on the same shared `aim_edge` plumbing.

See the [migration guide](https://aim-dart.dev/server/guides/migration) for
the exact edits.

## 0.3.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.3.0)

## 0.2.0

- **Breaking:** `c.req.workerEnv` / `c.req.workerContext` are replaced by `c.env` / `c.executionContext` (extension on `Context`).
- **Breaking:** follows `aim_core`'s rename of `Env` → `Variables` and `envFactory` → `variablesFactory` (re-exported).
- `c.env` now returns `Bindings?` (`string(name)`, `get(name)`, `has(name)`, `raw`) instead of a bare `JSObject?`.
- New `c.cf` returns `CfProperties?` with typed getters for Cloudflare's request metadata (country, colo, city, asn, ...).

## 0.1.1

Initial release. Runs `aim_core` applications on Cloudflare workerd via `dart compile wasm`.
