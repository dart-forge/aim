<div align="center">
  <img src="docs/public/banner.png" alt="Aim – A lightweight, fast web framework for Dart" width="1536">
</div>

<hr />

A lightweight, modular web framework for Dart with native PostgreSQL support and type-safe ORM.

## Features

- **Web Server** - Fast HTTP server with routing and middleware
- **Database** - Native PostgreSQL driver with SSL/TLS support
- **ORM** - Type-safe query builder with Dart 3 Record syntax
- **CLI** - Project scaffolding, hot reload, and database migrations
- **Modular** - Use only what you need

## Packages

### Server

| Package | pub.dev | Description |
|---------|---------|-------------|
| [aim_core](./packages/aim_core) | [![Pub Version](https://img.shields.io/pub/v/aim_core)](https://pub.dev/packages/aim_core) | Platform-independent core (routing, middleware, request/response) |
| [aim_server](./packages/aim_server) | [![Pub Version](https://img.shields.io/pub/v/aim_server)](https://pub.dev/packages/aim_server) | dart:io adapter: runs an Aim app on HttpServer |
| [aim_edge](./packages/aim_edge) | [![Pub Version](https://img.shields.io/pub/v/aim_edge)](https://pub.dev/packages/aim_edge) | Shared plumbing for edge runtimes (dart compile wasm); adapter authors build on this |
| [aim_workers](./packages/aim_workers) | — | Cloudflare workerd adapter: runs an Aim app as a Worker |
| [aim_deno](./packages/aim_deno) | — | Deno adapter: runs an Aim app on Supabase Edge Functions and other Deno runtimes |
| [aim_functions](./packages/aim_functions) | — | Cloud Functions for Firebase adapter: runs an Aim app as an HTTP function (experimental) |
| [aim_server_cors](./packages/aim_server_cors) | [![Pub Version](https://img.shields.io/pub/v/aim_server_cors)](https://pub.dev/packages/aim_server_cors) | CORS middleware |
| [aim_server_cookie](./packages/aim_server_cookie) | [![Pub Version](https://img.shields.io/pub/v/aim_server_cookie)](https://pub.dev/packages/aim_server_cookie) | Cookie management |
| [aim_server_form](./packages/aim_server_form) | [![Pub Version](https://img.shields.io/pub/v/aim_server_form)](https://pub.dev/packages/aim_server_form) | Form data parsing |
| [aim_server_multipart](./packages/aim_server_multipart) | [![Pub Version](https://img.shields.io/pub/v/aim_server_multipart)](https://pub.dev/packages/aim_server_multipart) | File upload handling |
| [aim_server_static](./packages/aim_server_static) | [![Pub Version](https://img.shields.io/pub/v/aim_server_static)](https://pub.dev/packages/aim_server_static) | Static file serving |
| [aim_server_logger](./packages/aim_server_logger) | [![Pub Version](https://img.shields.io/pub/v/aim_server_logger)](https://pub.dev/packages/aim_server_logger) | HTTP logging |
| [aim_server_sse](./packages/aim_server_sse) | [![Pub Version](https://img.shields.io/pub/v/aim_server_sse)](https://pub.dev/packages/aim_server_sse) | Server-Sent Events |
| [aim_server_jwt](./packages/aim_server_jwt) | [![Pub Version](https://img.shields.io/pub/v/aim_server_jwt)](https://pub.dev/packages/aim_server_jwt) | JWT authentication |
| [aim_server_basic_auth](./packages/aim_server_basic_auth) | [![Pub Version](https://img.shields.io/pub/v/aim_server_basic_auth)](https://pub.dev/packages/aim_server_basic_auth) | Basic authentication |
| [aim_server_testing](./packages/aim_server_testing) | [![Pub Version](https://img.shields.io/pub/v/aim_server_testing)](https://pub.dev/packages/aim_server_testing) | Test utilities |

### Database & ORM

| Package | pub.dev | Description |
|---------|---------|-------------|
| [aim_database](./packages/aim_database) | [![Pub Version](https://img.shields.io/pub/v/aim_database)](https://pub.dev/packages/aim_database) | Database abstraction layer |
| [aim_postgres](./packages/aim_postgres) | [![Pub Version](https://img.shields.io/pub/v/aim_postgres)](https://pub.dev/packages/aim_postgres) | Native PostgreSQL driver |
| [aim_orm](./packages/aim_orm) | [![Pub Version](https://img.shields.io/pub/v/aim_orm)](https://pub.dev/packages/aim_orm) | ORM abstraction layer |
| [aim_orm_postgres](./packages/aim_orm_postgres) | [![Pub Version](https://img.shields.io/pub/v/aim_orm_postgres)](https://pub.dev/packages/aim_orm_postgres) | PostgreSQL ORM implementation |
| [aim_orm_codegen](./packages/aim_orm_codegen) | [![Pub Version](https://img.shields.io/pub/v/aim_orm_codegen)](https://pub.dev/packages/aim_orm_codegen) | ORM code generator |

### CLI

| Package | pub.dev | Description |
|---------|---------|-------------|
| [aim_cli](./packages/aim_cli) | [![Pub Version](https://img.shields.io/pub/v/aim_cli)](https://pub.dev/packages/aim_cli) | CLI tools (scaffolding, hot reload, migrations) |

## Documentation

**[aim-dart.dev](https://aim-dart.dev)**

- [Server Guide](https://aim-dart.dev/server/)
- [Database & ORM](https://aim-dart.dev/database/)
- [CLI Commands](https://aim-dart.dev/cli/commands)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License. See [LICENSE](./LICENSE) for details.
