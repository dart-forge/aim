# workers-sample

Aim running on Cloudflare workerd, compiled to WebAssembly.

```bash
dart run ../../packages/aim_cli/bin/aim.dart build   # inside this repo (or `aim build` once aim_cli is installed)
npx wrangler@4 dev                                   # http://localhost:8787
curl http://localhost:8787/users/42
curl -N http://localhost:8787/sse
```

Requires Node (see `mise.toml` at the repo root) and network access for `npx wrangler` on first run.
