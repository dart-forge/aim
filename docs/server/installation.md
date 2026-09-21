---
title: Installation - Aim Framework
description: Get started with Aim framework for Dart. Learn how to install and create your first serverside Dart application.
---

# Installation

Get Aim installed and set up your development environment.

## Prerequisites

- [Dart SDK](https://dart.dev/get-dart) 3.10.0 or higher
- A code editor (VS Code, IntelliJ IDEA, etc.)

## Using Aim CLI (Recommended)

The easiest way to start a new project is using the Aim CLI:

```bash
# Install the Aim CLI
dart install aim_cli

# Create a new project
aim create my_app

# Navigate to the project
cd my_app

# Start the development server
aim dev
```

The CLI will:
- Create a new Dart project with the correct structure
- Install dependencies
- Set up a basic application
- Start the development server with hot reload

### Cloudflare Workers

To target Cloudflare Workers instead of the Dart VM, pass `--target edge`:

```bash
aim create my_worker --target edge
cd my_worker
dart pub get
aim dev   # compiles to WebAssembly and starts wrangler dev
```

This requires Node.js (the CLI runs `npx wrangler@4`). See [Cloudflare Workers](/server/edge) for bindings, deployment, and what differs from the VM.

### Cloud Functions

To target Cloud Functions for Firebase, pass `--target functions`:

```bash
aim create my_api --target functions
cd my_api
dart pub get
aim dev   # starts the Firebase emulator
```

`aim build` does nothing for this target — the Firebase CLI itself compiles your app during `firebase deploy --only functions`. See [Cloud Functions for Firebase](/server/functions) for the full setup; Dart support there is experimental.

## Manual Setup

If you prefer to set up manually:

1. Create a new Dart project:

```bash
dart create my_app
cd my_app
```

2. Add Aim to your `pubspec.yaml`:

```yaml
dependencies:
  aim_server: ^0.1.1

dev_dependencies:
  lints: ^5.0.0
```

3. Install dependencies:

```bash
dart pub get
```

## Next Steps

Now that you have Aim installed, head over to the [Quick Start](/server/quick-start) guide to build your first application.
