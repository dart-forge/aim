# aim_mysql

A native MySQL driver for Dart.

[Documentation](https://aim-dart.dev/database/drivers/mysql) | [pub.dev](https://pub.dev/packages/aim_mysql)

## Overview

`aim_mysql` is a pure Dart MySQL driver that implements the MySQL wire protocol from scratch, with no native dependency. It targets MySQL 8.0 and 8.4, and supports TLS with certificate verification, the `caching_sha2_password` and `mysql_native_password` authentication plugins, prepared statements with a per-connection cache, named (`:name`) and positional (`?`) parameter binding, and transactions with automatic rollback.

## Installation

```yaml
dependencies:
  aim_mysql: ^0.4.0
```

## Documentation

For detailed usage, examples, and API reference, see the [documentation](https://aim-dart.dev/database/drivers/mysql).
