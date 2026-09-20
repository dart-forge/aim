---
title: CLI Configuration - Aim
description: Configure Aim CLI via pubspec.yaml. Entry points, environment variables, and development settings.
head:
  - - meta
    - name: keywords
      content: Aim CLI config, pubspec.yaml, environment variables, Dart configuration
---

# Configuration

Configure Aim CLI via `pubspec.yaml`, under a top-level `aim:` key.

## Settings

| Key | Used by | Description | Default |
|---|---|---|---|
| `target` | `aim dev`, `aim build` | Where the app runs: `server`, `edge` or `functions` | `server` |
| `entry` | `aim dev`, `aim build` | Entry point | `bin/server.dart` for `server` and `functions`, or `lib/main.dart` for `edge` |
| `env` | `aim dev` | Environment variables passed to the app | none |
| `database.url` | `aim db:*` | Database connection URL | required by `aim db:*` |
| `database.schema` | `aim db:generate` | Path to table definitions, a file or a directory | `lib/schema` |

Values under `env` and `database` go through [variable expansion](#variable-expansion-formats), so secrets stay out of the file.

## Basic Configuration

```yaml
name: my_app
description: My Aim application

dependencies:
  aim_server: ^0.1.1

aim:
  entry: bin/server.dart
```

## Target

`aim.target` selects where the application runs. It changes what `aim dev` and `aim build` do and the default entry point.

| `target` | Runtime | `aim dev` | `aim build` | Default entry |
|---|---|---|---|---|
| `server` (default) | Dart VM with `aim_server` | `dart run` with restart on change | `dart compile exe` → `build/server` | `bin/server.dart` |
| `edge` | Cloudflare workerd with `aim_edge` | `dart compile wasm` + `npx wrangler@4 dev`, recompiles on change | `dart compile wasm` → `build/edge/` | `lib/main.dart` |
| `functions` | Cloud Functions for Firebase with `aim_functions` | `firebase emulators:start --only functions`; the emulator rebuilds on change | nothing — `firebase deploy --only functions` compiles | `bin/server.dart` |

```yaml
aim:
  target: edge
  entry: lib/main.dart
```

`aim.env` is not applied for `target: edge`; declare vars and bindings in `wrangler.jsonc` instead and read them with `c.env`. For `target: functions`, `aim.env` is passed to the Firebase emulator process, which the function process it spawns inherits.

## Environment Variables

### Static Values

```yaml
aim:
  entry: bin/server.dart
  env:
    PORT: "8080"
    HOST: "0.0.0.0"
    ENV: "development"
```

### Environment Variable Expansion

You can expand system environment variables:

```yaml
aim:
  env:
    DATABASE_URL: ${DATABASE_URL}
    JWT_SECRET: ${JWT_SECRET}
    API_KEY: ${API_KEY}
```

### Default Values

Default values when environment variables are not set:

```yaml
aim:
  env:
    PORT: ${PORT:8080}
    HOST: ${HOST:0.0.0.0}
    DATABASE_URL: ${DB_URL:postgresql://localhost/dev}
```

### Combined Example

```yaml
aim:
  entry: bin/server.dart
  env:
    # Static values
    ENV: "development"

    # With defaults
    PORT: ${PORT:8080}
    HOST: ${HOST:0.0.0.0}

    # Required (no default)
    DATABASE_URL: ${DATABASE_URL}
    JWT_SECRET: ${JWT_SECRET}
```

## Database

`aim.database` configures the `aim db:*` commands.

```yaml
aim:
  database:
    url: ${DATABASE_URL:postgresql://localhost:5432/mydb}
    schema: lib/schema
```

| Key | Description |
|---|---|
| `url` | Connection URL used by `db:migrate`, `db:rollback`, `db:reset` and `db:status` |
| `schema` | Where `db:generate` reads table definitions from. `--path` overrides it |

`url` is expanded like `aim.env`, so the connection string does not have to be
committed:

```bash
export DATABASE_URL="postgresql://user:pass@prod-host:5432/mydb"
aim db:migrate
```

A `${VAR}` that is not set and has no default reads as *not configured*, and the
command stops with `Database URL not found` instead of dialling an empty
address.

## Variable Expansion Formats

| Format | Description |
|--------|-------------|
| `$VAR_NAME` | Simple expansion |
| `${VAR_NAME}` | Braces expansion |
| `${VAR_NAME:default}` | With default value |

Expansion applies to the values under `aim.env` and `aim.database`.

## How It Works

When running `aim dev`:

1. Load `aim.env` from `pubspec.yaml`
2. Expand `${VAR}` with system environment variables
3. Merge with existing environment variables
4. Pass to application

## Example Workflow

### Development

```yaml
# pubspec.yaml
aim:
  entry: bin/server.dart
  env:
    PORT: ${PORT:3000}
    DATABASE_URL: ${DB_URL:postgresql://localhost/dev}
    DEBUG: "true"
```

```bash
# Uses defaults
aim dev
# PORT=3000, DATABASE_URL=postgresql://localhost/dev, DEBUG=true
```

### Production

```bash
# Override with environment variables
export PORT=8080
export DB_URL="postgresql://prod-server/mydb"
aim dev
# PORT=8080, DATABASE_URL=postgresql://prod-server/mydb, DEBUG=true
```

## Entry Point Resolution

Entry point is determined in this order:

1. `--entry` option (`aim dev --entry bin/api.dart`)
2. `aim.entry` in `pubspec.yaml`
3. Target default: `bin/server.dart` for `server` and `functions`, `lib/main.dart` for `edge`

## Watch Directories

Directories watched by `aim dev`:

- Default: `lib`, `bin`
- Customizable with `--watch` option

```bash
aim dev --watch lib,bin,routes,config
```

## Next Steps

- [Commands](/cli/commands) - CLI command reference
- [Server Quick Start](/server/quick-start) - Build your first app
