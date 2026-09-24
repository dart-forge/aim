---
title: aim_server - Web Framework for Dart
description: Lightweight, modular web framework for Dart. Context API, routing, middleware, and authentication for modern server-side applications.
head:
  - - meta
    - name: keywords
      content: Dart web framework, aim_server, REST API, middleware, routing, Dart server
---

# aim_server

A lightweight, modular web framework for Dart.

## Features

- **Context API** - Intuitive request/response handling inspired by Hono
- **Routing** - Path parameters, wildcards, and method-based routing
- **Middleware** - Composable middleware chain with early response support
- **Type-Safe** - Custom `Variables` classes for type-safe context variables
- **Modular** - Use only the middleware packages you need
- **Runs anywhere** - The same app runs on the Dart VM (`aim_server`), on [Cloudflare Workers](/server/workers) (`aim_workers`), on [Supabase Edge Functions](/server/supabase) (`aim_deno`), and, experimentally, on [Cloud Functions for Firebase](/server/functions) (`aim_functions`)

## Quick Start

### Installation

```bash
dart pub add aim_server
```

### Hello World

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';

void main() async {
  final app = Aim();

  app.get('/', (c) async {
    return c.json({'message': 'Hello, Aim!'});
  });

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
  print('Server running on http://localhost:8080');
}
```

### With Middleware

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_cors/aim_server_cors.dart';
import 'package:aim_server_logger/aim_server_logger.dart';

void main() async {
  final app = Aim();

  // Add middleware
  app.use(logger());
  app.use(cors());

  // Routes
  app.get('/users', (c) async {
    return c.json({'users': []});
  });

  app.post('/users', (c) async {
    final body = await c.req.json();
    return c.json({'created': body}, statusCode: 201);
  });

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
}
```

## Middleware Packages

| Package | Description |
|---------|-------------|
| [aim_server_cors](/server/middleware/cors) | CORS support |
| [aim_server_cookie](/server/middleware/cookie) | Cookie management |
| [aim_server_form](/server/middleware/form) | Form data parsing |
| [aim_server_multipart](/server/middleware/multipart) | File uploads |
| [aim_server_static](/server/middleware/static) | Static file serving |
| [aim_server_logger](/server/middleware/logger) | Request logging |
| [aim_server_sse](/server/middleware/sse) | Server-Sent Events |
| [aim_server_jwt](/server/auth/jwt) | JWT authentication |
| [aim_server_basic_auth](/server/auth/basic-auth) | Basic authentication |
| [aim_server_testing](/server/guides/testing) | Test utilities |

## Next Steps

- [Installation](/server/installation) - Detailed setup guide
- [Quick Start](/server/quick-start) - Build your first API
- [Cloudflare Workers](/server/workers) - Deploy the same app to the edge
- [Supabase Edge Functions](/server/supabase) - Deploy the same app on Deno
- [Cloud Functions for Firebase](/server/functions) - Deploy the same app as an HTTP function (experimental)
- [Routing](/server/concepts/routing) - Path parameters and wildcards
- [Middleware](/server/concepts/middleware) - Create custom middleware
