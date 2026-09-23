---
title: CLI Reference - Aim Framework
description: Complete Aim CLI guide. Create projects, run dev server with hot reload, build for production, and configure environments.
head:
  - - meta
    - name: keywords
      content: Aim CLI, Dart CLI, hot reload, dev server, production build, environment configuration
---

# CLI Reference

Complete guide to the Aim CLI tool.

## Installation

```bash
dart install aim_cli
```

## Commands

### `aim create`

Create a new Aim framework project.

**Usage:**
```bash
aim create <project_name>
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--target` | Project target: `server`, `workers`, `supabase` or `functions` | `server` |
| `--firebase-project` | Firebase project id written to `.firebaserc` (target: functions only — silently ignored for every other target). Pass an empty value to skip `.firebaserc` and bind a project later with `firebase use --add` | prompts when a terminal is attached |

**Example:**
```bash
aim create my_app
cd my_app
```

This command:
- Creates a new directory with the project name
- Generates project structure (bin/, lib/, test/)
- Creates `pubspec.yaml` with Aim dependencies
- Generates a basic server in `bin/server.dart`
- Prints the next steps (`dart pub get`, `aim dev`)

**With `--target workers`:**
```bash
aim create my_worker --target workers
cd my_worker
```

This scaffolds a Cloudflare workerd project instead:
- `lib/main.dart` - Dart entry point, ends with `app.serveWorkers()`
- `src/index.mjs` - JavaScript Worker entry point
- `wrangler.jsonc` - Wrangler configuration

The Worker name in `wrangler.jsonc` is the project name with underscores (`_`) replaced by hyphens (`-`), e.g. `my_worker` becomes `my-worker`. See [Cloudflare Workers](/server/workers) for the full setup.

**With `--target supabase`:**
```bash
aim create my_api --target supabase
cd my_api
```

This scaffolds a Supabase Edge Functions project:
- `lib/main.dart` - Dart entry point, ends with `app.serveDeno(basePath: 'my_api')`
- `supabase/functions/my_api/index.ts` - the function's Deno entry point
- `supabase/config.toml` - `project_id` plus a `static_files` declaration for the compiled wasm

See [Supabase Edge Functions](/server/supabase) for the full setup, including why the app needs `basePath`.

`--target edge` is no longer accepted; use `--target workers`. A project whose `pubspec.yaml` still has `aim.target: edge` from before this split fails `aim dev`/`aim build` with an error naming the new target and dependency (`workers`/`aim_workers`).

**With `--target functions`:**
```bash
aim create my_api --target functions
cd my_api
```

This scaffolds a Cloud Functions for Firebase project, flat in one directory:
- `firebase.json` - Firebase config, with `"source": "."` next to `pubspec.yaml`
- `bin/server.dart` - hands the app to `firebase_functions`' `onRequest`
- `lib/src/server.dart` - `createApp()`, your routes
- `test/<project_name>_test.dart` - a starter test
- `README.md` - prerequisites, dev loop, and deploy steps for this project
- `.gitignore`
- `.firebaserc` - written only when a Firebase project id was given

It prompts for a Firebase project id (`Firebase project id (leave empty to set it up later): `) unless `--firebase-project` is passed. An empty answer skips `.firebaserc`; with no terminal attached and no `--firebase-project`, the prompt is skipped the same way. See [Cloud Functions for Firebase](/server/functions) for the full setup.

### `aim dev`

Start the development server with hot reload support.

**Usage:**
```bash
aim dev [options]
```

**Options:**

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--entry` | `-e` | Server entry point | `bin/server.dart` |
| `--host` | | Ignored (reserved) | — |
| `--port` | `-p` | Port passed to `wrangler dev` (target: workers only; rejected for target: supabase and target: functions) | 8787 (wrangler default) |
| `--hot-reload` | | Enable hot reload | `true` |
| `--no-hot-reload` | | Disable hot reload | |
| `--watch` | | Directories to watch (comma-separated) | `lib,bin`; `lib` for `target: workers` and `target: supabase` |

**Examples:**
```bash
# Start with default settings
aim dev

# Custom entry point
aim dev --entry bin/api.dart

# Disable hot reload
aim dev --no-hot-reload

# Watch additional directories
aim dev --watch lib,bin,routes

# Custom port
aim dev --port 3000
```

**How it works:**
- Watches specified directories for file changes
- Automatically restarts the server when files are modified
- Preserves terminal output history
- Loads environment variables from `pubspec.yaml`

**With `target: workers`:**
- Compiles the entry point to WebAssembly (`dart compile wasm`)
- Starts `npx wrangler@4 dev` to run the compiled Worker locally
- `--port` is passed through to wrangler
- Changes under `lib/` (or the watched directories) trigger a recompile; wrangler reloads the updated wasm automatically
- `--no-hot-reload` disables file watching entirely
- `aim.env` is ignored (with a warning) — configure vars and bindings in `wrangler.jsonc` instead
- Requires Node.js to be installed (for `npx`)

**With `target: supabase`:**
- Compiles the entry point to WebAssembly (`dart compile wasm`) into `supabase/functions/<name>/`, where `<name>` is the pubspec's `name`
- Checks whether the local Supabase stack is running (`supabase status`) and runs `supabase start` itself when it is not, before starting `supabase functions serve <name> --no-verify-jwt`
- The first run on a fresh checkout takes a few minutes: `supabase start` brings up Postgres, auth and storage, and applies this project's migrations and `seed.sql` to the local database
- The stack is left running when `aim dev` exits, including on Ctrl-C; run `supabase stop` to stop it
- `--port` is rejected; the function's port comes from `supabase/config.toml`
- Changes under `lib/` trigger a recompile; `supabase functions serve` picks up the rebuilt wasm without being restarted
- `aim.env` is ignored (with a warning) — set variables with `supabase secrets set` or `supabase/functions/.env` instead
- Requires the Supabase CLI (2.7.0+) and a running Docker daemon

**With `target: functions`:**
- Starts `firebase emulators:start --only functions`
- The emulator runs `build_runner watch` itself, so edits are picked up while `aim dev` keeps running, without the CLI adding a second rebuild loop — `--hot-reload` and `--watch` have no effect
- `--entry` / `aim.entry` have no effect either: Firebase resolves the entry point itself, from `firebase.json` and its own convention
- `--host` is silently ignored
- `--port` is rejected; set the port in `firebase.json` under `emulators.functions.port` instead
- `aim.env` is passed to the emulator process, which the function process it spawns inherits
- Falls back to a `demo-` project id (derived from the package name) when there's no `.firebaserc`
- Requires the Firebase CLI, logged in, with `firebase experiments:enable dartfunctions` run once

### `aim build`

Compile the server for production deployment.

**Usage:**
```bash
aim build [options]
```

**Options:**

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--entry` | `-e` | Server entry point | `bin/server.dart` or `pubspec.yaml` |
| `--output` | `-o` | Output file path | `build/server` |

**Examples:**
```bash
# Build with default settings
aim build

# Custom entry point
aim build --entry bin/api.dart

# Custom output path
aim build --output dist/my-server

# Both custom
aim build --entry bin/api.dart --output dist/api-server
```

**Output:**
```
🔨 Compiling for production...
📁 Entry point: bin/server.dart
📦 Output: build/server

✅ Build successful!

📦 Executable: build/server

Next steps:
  # Run locally
  ./build/server

  # Build Docker image
  docker build -t my-app .
```

**With `target: workers`:**
- Compiles the entry point to WebAssembly (`dart compile wasm`)
- Output is `build/workers/main.wasm` and `build/workers/main.mjs` (with `CompiledApp` already exported)
- `--output` is a directory (default `build/workers`), not a file path
- Next step: `npx wrangler@4 deploy`

**With `target: supabase`:**
- Compiles the entry point to WebAssembly (`dart compile wasm`)
- Output is `supabase/functions/<name>/main.wasm` and `main.mjs`, where `<name>` is the pubspec's `name`
- `--output` is a directory (default `supabase/functions/<name>`), not a file path
- Next step: `supabase functions deploy <name>`, not `--use-api` — `--use-api` skips the bundling step that places `main.wasm` next to the deployed `index.ts`, which is what `static_files` in `supabase/config.toml` depends on

**With `target: functions`:**
- Does nothing — prints a message and exits; `firebase deploy --only functions` compiles on your machine and uploads the result
- `--entry` / `aim.entry` and `--output` are silently ignored: there is nothing to compile and nowhere to write it

## Configuration

### pubspec.yaml

Configure Aim CLI behavior in your `pubspec.yaml`:

```yaml
name: my_app
description: My Aim application

dependencies:
  aim_server: ^0.4.0

# Aim CLI configuration
aim:
  # Entry point (optional)
  entry: bin/server.dart

  # Environment variables (optional)
  env:
    PORT: "8080"
    HOST: "0.0.0.0"
    DATABASE_URL: "postgresql://localhost/mydb"
    JWT_SECRET: ${JWT_SECRET}  # Expand from system environment
```

### Environment Variables

The `aim.env` section supports multiple formats:

**1. Static values:**
```yaml
aim:
  env:
    PORT: "8080"
    ENV: "development"
```

**2. Environment variable expansion:**
```yaml
aim:
  env:
    DATABASE_URL: ${DATABASE_URL}  # Reads from system environment
    JWT_SECRET: ${JWT_SECRET}
    API_KEY: ${API_KEY}
```

**3. Default values:**
```yaml
aim:
  env:
    PORT: ${PORT:8080}              # Use $PORT, fallback to 8080
    HOST: ${HOST:0.0.0.0}           # Use $HOST, fallback to 0.0.0.0
    DATABASE_URL: ${DB_URL:postgresql://localhost/dev}
```

**4. Mixed:**
```yaml
aim:
  env:
    PORT: ${PORT:3000}              # With default
    DATABASE_URL: ${DATABASE_URL}   # Required (no default)
    DEBUG: "true"                   # Static value
```

**Supported formats:**
- `$VAR_NAME` - Simple expansion
- `${VAR_NAME}` - Braces expansion
- `${VAR_NAME:default}` - With default value

When you run `aim dev`, these variables are:
1. Read from `pubspec.yaml`
2. Expanded using system environment variables
3. Merged with existing environment
4. Passed to your application

**Example 1 - With defaults:**
```yaml
# pubspec.yaml
aim:
  env:
    PORT: ${PORT:3000}                    # Defaults to 3000
    DATABASE_URL: ${DB_URL:postgresql://localhost/dev}
    DEBUG: ${DEBUG:false}
```

```bash
# Terminal (no environment variables set)
aim dev

# Your application receives:
# PORT=3000
# DATABASE_URL=postgresql://localhost/dev
# DEBUG=false
```

**Example 2 - Override defaults:**
```yaml
# pubspec.yaml
aim:
  env:
    PORT: ${PORT:3000}
    DATABASE_URL: ${DB_URL:postgresql://localhost/dev}
```

```bash
# Terminal (with environment variables)
export PORT=8080
export DB_URL="postgresql://production/mydb"
aim dev

# Your application receives:
# PORT=8080
# DATABASE_URL=postgresql://production/mydb
```

## Development Workflow

### 1. Create Project

```bash
aim create my_api
cd my_api
```

### 2. Development

```bash
# Start dev server with hot reload
aim dev

# Edit files in lib/ or bin/
# Server automatically restarts
```

### 3. Build for Production

```bash
# Compile to executable
aim build

# Test the build
./build/server

# Deploy
scp build/server user@server:/app/
```

## Tips & Tricks

### Quick Project Setup

```bash
aim create my_app && cd my_app && aim dev
```

### Development with Custom Port

```yaml
# pubspec.yaml
aim:
  env:
    PORT: "3000"
```

```bash
aim dev
# Server runs on port 3000
```

### Multiple Environments

```bash
# Development
aim dev

# Production build
ENV=production aim build
./build/server
```

### Debugging Without Hot Reload

```bash
aim dev --no-hot-reload
# Use Dart debugger in IDE
```

### Watch Specific Directories

```bash
aim dev --watch lib,bin,routes,config
```

### Custom Entry Points

Useful for microservices:

```bash
# API server
aim dev --entry bin/api.dart --port 8080

# Admin server
aim dev --entry bin/admin.dart --port 8081
```

## Troubleshooting

### "pubspec.yaml not found"

Make sure you're in the project root directory:

```bash
cd my_project
aim dev
```

### "Entry point not found"

Check that the entry file exists:

```bash
ls bin/server.dart
# or specify custom entry
aim dev --entry bin/api.dart
```

### Hot Reload Not Working

1. Check you're editing files in watched directories (`lib/`, `bin/`)
2. Try disabling and re-enabling:
   ```bash
   aim dev --no-hot-reload  # Test without
   aim dev                   # Re-enable
   ```

### Port Already in Use

```bash
# Find and kill process
lsof -i :8080
kill -9 <PID>

# Or use different port
aim dev --port 3000
```

### Environment Variables Not Loading

Check your `pubspec.yaml` formatting:

```yaml
aim:
  env:
    PORT: "8080"  # Must be quoted
    DEBUG: "true" # Booleans as strings
```

Make sure system variables are exported:

```bash
export DATABASE_URL="postgresql://localhost/db"
aim dev
```

## Database Commands

Aim CLI provides database migration tools powered by `aim_orm`.

### `aim db:generate`

Generate migration SQL from schema changes.

**Usage:**
```bash
aim db:generate [options]
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--name` | Migration name | Auto-generated timestamp |
| `--path` | Path to table definitions | `aim.database.schema`, or `lib/schema` |

**Example:**
```bash
aim db:generate --name add_users_table
```

This command:
- Compares your current schema definitions with the last migration
- Detects added/removed tables, columns, indexes, and constraints
- Generates both UP and DOWN SQL migrations
- Creates a file in `migrations/` directory

**Output:**
```
migrations/
└── 20250121_120000_add_users_table.sql
```

For detailed usage, see [Migrations Guide](/database/orm/migrations).

### `aim db:migrate`

Apply pending migrations to the database.

**Usage:**
```bash
aim db:migrate [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--target` | Apply up to specific migration |

**Example:**
```bash
# Apply all pending migrations
aim db:migrate

# Apply up to specific migration
aim db:migrate --target 20250121_120000_add_users_table
```

### `aim db:rollback`

Rollback applied migrations.

**Usage:**
```bash
aim db:rollback [options]
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--step` | Number of migrations to rollback | 1 |
| `--target` | Rollback to specific migration | |

**Example:**
```bash
# Rollback last migration
aim db:rollback

# Rollback last 3 migrations
aim db:rollback --step 3

# Rollback to specific migration
aim db:rollback --target 20250121_100000_initial
```

### `aim db:reset`

Drop the database, recreate it, and apply every migration from scratch.
Connects to the admin `postgres` database to drop/create the target database
named in `aim.database.url`, then replays all migration files.

**Usage:**
```bash
aim db:reset [options]
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--force`, `-f` | Skip the confirmation prompt | prompts |

**Example:**
```bash
aim db:reset            # asks "Are you sure? [y/N]" first
aim db:reset --force    # for CI or scripts
```

::: warning Destructive
This drops the database named in `aim.database.url` and everything in it,
then recreates it and reapplies every migration. There is no undo.
:::

### `aim db:status`

Show migration status.

**Usage:**
```bash
aim db:status
```

**Output:**
```
Migration Status:

  [✓] 20250121_100000_initial           Applied: 2025-01-21 10:00:00
  [✓] 20250121_110000_add_posts_table   Applied: 2025-01-21 11:00:00
  [ ] 20250121_120000_add_comments      Pending

Applied: 2 / Total: 3
```

### Database Configuration

Configure database connection in `pubspec.yaml`. See
[Configuration](/cli/configuration#database) for every key.

```yaml
aim:
  database:
    url: ${DATABASE_URL:postgresql://localhost:5432/mydb}
```

Or use environment variables:

```bash
export DATABASE_URL="postgresql://user:pass@localhost:5432/mydb"
aim db:migrate
```

## Next Steps

- Read the [Quick Start](/server/quick-start) guide
- Learn about [Routing](/server/concepts/routing)
- Explore [Middleware](/server/middleware/)
- Learn about [Migrations](/database/orm/migrations)
