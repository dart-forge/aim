# aim_postgres

A native PostgreSQL driver for Dart.

[Documentation](https://aim-dart.dev/database/drivers/postgres) | [pub.dev](https://pub.dev/packages/aim_postgres)

## Overview

`aim_postgres` is a pure Dart PostgreSQL driver that implements the PostgreSQL wire protocol from scratch. It supports multiple SSL/TLS modes including certificate verification, authentication methods (cleartext, MD5, SCRAM-SHA-256), both Simple and Extended Query protocols, named (`:name`) and positional (`$1`) parameter binding, and full transaction support with automatic rollback.

## Installation

```yaml
dependencies:
  aim_postgres: ^0.4.0
```

## Documentation

For detailed usage, examples, and API reference, see the [documentation](https://aim-dart.dev/database/drivers/postgres).
