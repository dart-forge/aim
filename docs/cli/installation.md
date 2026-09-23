---
title: CLI Installation - Aim
description: Install the Aim CLI tool for project scaffolding, development server, and production builds.
head:
  - - meta
    - name: keywords
      content: Dart CLI install, aim_cli setup, Dart development tools
---

# Installation

## Global Installation

Install Aim CLI globally:

```bash
dart install aim_cli
```

## Verify Installation

`aim` does not register a `--version` flag. Confirm the install with `--help`,
which lists every command:

```bash
aim --help
```

Output:
```
Command-line tool for Aim framework

Usage: aim <command> [arguments]

Global options:
-h, --help    Print this usage information.

Available commands:
  build         Compile the server for production deployment
  create        Create a new Aim framework project
  db:generate   Generate migration from table definitions
  db:migrate    Apply pending migrations to the database
  db:reset      Drop database, recreate it, and apply all migrations
  db:rollback   Rollback the last applied migration(s)
  db:status     Show migration status
  dev           Start development server (with hot reload support)

Run "aim help <command>" for more information about a command.
```

To check which version of `aim_cli` is installed, use pub itself:

```bash
dart pub global list
```

## PATH Configuration

To use globally installed commands, add Dart's pub-cache/bin directory to your PATH.

### macOS / Linux

```bash
# ~/.bashrc or ~/.zshrc
export PATH="$PATH":"$HOME/.pub-cache/bin"
```

### Windows

```powershell
# PowerShell
$env:PATH += ";$env:APPDATA\Pub\Cache\bin"
```

## Update

Update to the latest version:

```bash
dart install aim_cli
```

## Uninstall

```bash
dart pub global deactivate aim_cli
```

## Next Steps

- [Commands](/cli/commands) - Available CLI commands
- [Configuration](/cli/configuration) - Environment setup
