## 0.3.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.3.0)

## 0.2.0

- **Breaking:** `c.req.workerEnv` / `c.req.workerContext` are replaced by `c.env` / `c.executionContext` (extension on `Context`).
- **Breaking:** follows `aim_core`'s rename of `Env` → `Variables` and `envFactory` → `variablesFactory` (re-exported).
- `c.env` now returns `Bindings?` (`string(name)`, `get(name)`, `has(name)`, `raw`) instead of a bare `JSObject?`.
- New `c.cf` returns `CfProperties?` with typed getters for Cloudflare's request metadata (country, colo, city, asn, ...).

## 0.1.1

Initial release. Runs `aim_core` applications on Cloudflare workerd via `dart compile wasm`.
