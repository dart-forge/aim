# aim_cli

Command-line tools for the Aim framework.

[Documentation](https://aim-dart.dev/cli/) | [pub.dev](https://pub.dev/packages/aim_cli)

## Overview

`aim_cli` provides command-line tools for creating and managing Aim framework projects. It includes project scaffolding with `aim create`, a development server with hot reload using `aim dev`, and database migration tools. The CLI watches for file changes and automatically restarts the server during development for fast iteration. Set `aim: target: workers` in pubspec.yaml to build for Cloudflare workerd with `aim_workers`: `aim build` compiles to WebAssembly and `aim dev` runs `wrangler dev`. Set `aim: target: supabase` to build for Supabase Edge Functions with `aim_deno`: `aim build` compiles to WebAssembly and `aim dev` runs `supabase functions serve`. Set `aim: target: functions` to run on Cloud Functions for Firebase with `aim_functions`: `aim dev` starts the Firebase emulator, and `aim build` is a no-op since the Firebase CLI compiles and deploys on its own.

## Installation

```bash
dart install aim_cli
```

## Documentation

For detailed usage, commands, and configuration options, see the [documentation](https://aim-dart.dev/cli/).
