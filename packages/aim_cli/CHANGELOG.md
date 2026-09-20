## Unreleased

- `aim.target: functions` in pubspec.yaml. `aim create --target functions` scaffolds a flat Cloud Functions for Firebase project (`firebase.json` with `"source": "."` next to `pubspec.yaml`, `bin/server.dart`, `lib/src/server.dart`, and an optional `.firebaserc`). `aim dev` starts `firebase emulators:start --only functions`; `aim build` is a no-op for this target, since the Firebase CLI compiles and deploys on its own.

## 0.2.0

- Requires analyzer ^14.0.0.
- `release:bump` now also updates the `aim_*` dependency pins inside the `aim create` templates.
- `aim.target` (`server` | `edge`) in pubspec.yaml. With `edge`, `aim build` runs `dart compile wasm` into `build/edge/` and `aim dev` runs `npx wrangler@4 dev` with wasm recompilation on change.
- `aim create --target edge` scaffolds a Cloudflare workerd project (`lib/main.dart`, `src/index.mjs`, `wrangler.jsonc`).
- `aim:` configuration is now parsed with `package:yaml`. Entry resolution is `--entry` > `aim.entry` > default for both `dev` and `build` (previously `dev` let `aim.entry` override `--entry`).
- Server template's `aim_server` pin is kept in sync with the release version by `release:bump` (was hard-coded `^0.0.6`).

## 0.1.1

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.1.1)


## 0.1.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/v0.1.0)


## 0.0.2

Production build and Docker support.

### Features

- Production Build:
  - `aim build` command to compile server for production deployment
  - Native executable compilation using `dart compile exe`
  - Automatic entry point detection from `pubspec.yaml`
  - Configurable output path with `--output` option
  - Default output: `build/server`
- Docker Support:
  - Dockerfile template with multi-stage build
  - Optimized for minimal image size using `scratch` base
  - `.dockerignore` template to exclude unnecessary files
  - Production-ready Docker configuration
- Enhanced Project Templates:
  - Updated README with production deployment instructions
  - Environment variable usage examples for native and Docker deployments
  - Security best practices for environment variable handling
  - Simplified `pubspec.yaml` with `aim_server: ^0.0.6`

### Commands

- `aim build [options]` - Compile server for production deployment
  - `-e, --entry` - Specify server entry point
  - `-o, --output` - Specify output file path

### Security

- Environment variables are not embedded at compile time
- Runtime environment variable support for secure configuration management
- Compatible with Docker secrets and Kubernetes ConfigMaps

## 0.0.1

Initial release of aim_cli - Command-line tools for the Aim web framework.

### Features

- Project Scaffolding:
  - `aim create` command to generate new Aim projects
  - Pre-configured project structure with best practices
  - Automatic generation of example routes and middleware
- Development Server:
  - `aim dev` command to start development server
  - Hot reload support with automatic server restart on file changes
  - Configurable entry point
  - Environment variable support from `pubspec.yaml`
- File Watching:
  - Monitors `.dart` files and `pubspec.yaml` for changes
  - Debounced file watching (500ms) to avoid excessive restarts
  - Configurable watch directories
- Process Management:
  - Graceful shutdown with SIGTERM
  - Force kill fallback with SIGKILL
  - Clean process lifecycle management
- Project Validation:
  - Project name validation (lowercase, alphanumeric, underscores)
  - Reserved word checking
  - Directory existence validation

### Supported

- Dart SDK: `^3.10.0`
- Platforms: All platforms supported by Dart (Linux, macOS, Windows)
- Installation: `dart install aim_cli` (Dart 3.10+)

### Commands

- `aim create <project_name>` - Create a new Aim project
- `aim dev [options]` - Start development server with hot reload

### What's Included

- Project templates for quick start
- Hot reload infrastructure
- File watching utilities
- Environment variable expansion
- Process management utilities
