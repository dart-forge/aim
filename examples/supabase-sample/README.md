# supabase-sample

Aim running on Supabase Edge Functions, compiled to WebAssembly.

## Prerequisites

```bash
npm install -g supabase
docker info      # Docker must be running
```

## Development

```bash
dart run ../../packages/aim_cli/bin/aim.dart dev   # inside this repo (or `aim dev` once aim_cli is installed)
curl http://localhost:54321/functions/v1/supabase_sample/users/42
```

`aim dev` starts the local Supabase stack itself if it is not already
running, applying this project's migrations and `seed.sql` to the local
database. The stack stays up after `aim dev` exits — run `supabase stop`
when you want to stop it.

## Deploy

```bash
dart run ../../packages/aim_cli/bin/aim.dart build   # supabase/functions/supabase_sample/main.wasm + main.mjs
supabase functions deploy supabase_sample
```

Deploy with the CLI, not `--use-api`: `--use-api` skips the bundling step
that places `main.wasm` next to the deployed `index.ts`, which is what
`static_files` in `supabase/config.toml` depends on.
