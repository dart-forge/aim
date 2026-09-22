## 0.4.0

- First release. A MySQL driver for `aim_database`, written as a pure Dart
  wire-protocol implementation with no native dependency.
- MySQL 8.0 and 8.4. `caching_sha2_password` and `mysql_native_password`,
  including the public-key path for full authentication over a plaintext
  connection.
- TLS through `sslmode`, defaulting to `prefer`.
- Always uses prepared statements, with a per-connection cache.
- Named (`:name`) and positional (`?`) parameters.
