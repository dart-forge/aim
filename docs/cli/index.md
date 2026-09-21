---
title: aim_cli - Development Tools for Dart
description: CLI tools for Aim development. Create projects, run dev server with hot reload, and build for production.
head:
  - - meta
    - name: keywords
      content: Dart CLI, aim_cli, hot reload, dev server, Dart build, project scaffolding
---

# aim_cli

Development tools for the Aim ecosystem.

## Features

- **Project Scaffolding** - Create new projects with `aim create`
- **Development Server** - Hot reload with `aim dev`
- **Production Build** - Compile to native executable with `aim build`
- **Environment Configuration** - Manage env variables via `pubspec.yaml`
- **Edge Targets** - `aim.target: workers` builds for Cloudflare workerd with `aim_workers`; `aim.target: supabase` builds for Supabase Edge Functions with `aim_deno`. Both compile to WebAssembly with `aim build`. See [Configuration](/cli/configuration#target).

## Quick Start

### Installation

```bash
dart install aim_cli
```

### Create a Project

```bash
aim create my_app
cd my_app
```

### Start Development Server

```bash
aim dev
```

Output:
```
🚀 Starting development server...
📁 Watching: lib, bin
🔥 Hot reload enabled

Server running on http://localhost:8080
```

### Build for Production

```bash
aim build
```

Output:
```
🔨 Compiling for production...
📁 Entry point: bin/server.dart
📦 Output: build/server

✅ Build successful!
```

## Commands

| Command | Description |
|---------|-------------|
| `aim create <name>` | Create a new project |
| `aim dev` | Start dev server with hot reload |
| `aim build` | Compile for production |

## Configuration

Configure via `pubspec.yaml`:

```yaml
name: my_app

dependencies:
  aim_server: ^0.1.1

aim:
  entry: bin/server.dart
  env:
    PORT: "8080"
    DATABASE_URL: ${DATABASE_URL}
```

## Next Steps

- [Installation](/cli/installation) - Detailed setup
- [Commands](/cli/commands) - All CLI commands
- [Configuration](/cli/configuration) - Environment variables
