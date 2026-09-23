# aim_database

Database abstraction layer for Dart.

[Documentation](https://aim-dart.dev/database/) | [pub.dev](https://pub.dev/packages/aim_database)

## Overview

`aim_database` provides common interfaces for database drivers in the Aim ecosystem. It defines the `Database` and `Transaction` abstract classes that concrete database implementations must implement. This package is typically used as a dependency of database driver packages rather than installed directly.

For database functionality, use a concrete driver package like [aim_postgres](https://pub.dev/packages/aim_postgres).

## Installation

```yaml
dependencies:
  aim_database: ^0.4.0
```

## Documentation

For detailed usage, examples, and API reference, see the [documentation](https://aim-dart.dev/database/).
