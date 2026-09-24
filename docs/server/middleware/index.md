---
title: Middleware Overview - Aim Framework
description: Official middleware packages for Aim. CORS, JWT auth, cookies, logging, file uploads, SSE, and more for Dart server applications.
head:
  - - meta
    - name: keywords
      content: Dart middleware, CORS, JWT authentication, cookies, logging, file upload, SSE, Aim middleware packages
---

# Middleware Overview

Aim provides a rich ecosystem of official middleware packages for common web application needs. Each package is published separately, allowing you to include only what you need.

::: tip Runs on edge runtimes too
The `aim_server_*` middleware packages (cors, cookie, form, logger, sse, jwt, basic_auth) and `aim_server_multipart`'s parsing depend only on `aim_core` and work unchanged on Cloudflare workerd (via `aim_workers`) and on Deno-based runtimes (via `aim_deno`). `aim_server_static` and `aim_server_multipart`'s `UploadedFile.saveTo()` need the file system and are VM-only.
:::

## Available Middleware

Every `aim_server_*` package below is versioned and released together with the
rest of the `aim_*` packages (see the [Migration Guide](/server/guides/migration)),
so no per-package version is listed here — check the [pub.dev
listing](https://pub.dev/packages?q=publisher%3Adart-forge.dev) or the
package's own page for the current version.

### Core Features

| Package | Description |
|---------|-------------|
| [CORS](/server/middleware/cors) | Cross-Origin Resource Sharing support |
| [Logger](/server/middleware/logger) | HTTP request/response logging |
| [Static Files](/server/middleware/static) | Serve static files securely |

### Data Handling

| Package | Description |
|---------|-------------|
| [Cookie](/server/middleware/cookie) | Secure cookie management |
| [Form](/server/middleware/form) | Parse form data (application/x-www-form-urlencoded) |
| [Multipart](/server/middleware/multipart) | Handle file uploads (multipart/form-data) |

### Real-time

| Package | Description |
|---------|-------------|
| [SSE](/server/middleware/sse) | Server-Sent Events support |

### Authentication

| Package | Description |
|---------|-------------|
| [JWT Auth](/server/auth/jwt) | JSON Web Token authentication |
| [Basic Auth](/server/auth/basic-auth) | HTTP Basic Authentication (RFC 7617) |

## Installation

Add middleware packages to your `pubspec.yaml`:

```yaml
dependencies:
  aim_server: ^0.4.0
  aim_server_cors: ^0.4.0
  aim_server_logger: ^0.4.0
  aim_server_jwt: ^0.4.0
```

Then run:

```bash
dart pub get
```

## Quick Start

Most middleware follows a similar usage pattern:

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_logger/aim_server_logger.dart';
import 'package:aim_server_cors/aim_server_cors.dart';

void main() async {
  final app = Aim();

  // Add middleware with app.use()
  app.use(logger());
  app.use(cors());

  // Your routes
  app.get('/', (c) async => c.text('Hello!'));

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
}
```

## Middleware Order

`app.use()` appends to one list that runs, in registration order, for
**every** request — the order controls what happens *before* the others
in the chain, not *which routes* a middleware applies to. `app.use(jwt())`
below does not exempt routes added earlier or later; `jwt` itself has to
be told which paths to skip (see [Public + Protected Routes](#public-protected-routes)):

```dart
final app = Aim();

// 1. Logger (first to capture everything)
app.use(logger());

// 2. CORS (before authentication, so preflight requests are handled)
app.use(cors());

// 3. Authentication (runs for every route, including ones registered above)
app.use(jwt());

// 4. Your routes
app.get('/protected', handler);
```

**Best practices:**
- Logger should be first to capture all requests
- CORS should be early to handle preflight requests
- Use each middleware's own exclusion option (such as `JwtOptions.excludedPaths`) to leave specific routes unauthenticated — registration order does not scope middleware to a subset of routes
- Error handlers should wrap other middleware

## Middleware That Requires Variables

Some middleware requires custom `Variables` classes:

```dart
import 'package:aim_server_jwt/aim_server_jwt.dart';

final app = Aim<JwtVariables>(
  variablesFactory: () => JwtVariables.create(
    JwtOptions(
      algorithm: HS256(
        secretKey: SecretKey(secret: 'your-secret-key-at-least-32-chars'),
      ),
    ),
  ),
);

app.use(jwt());

app.get('/protected', (c) async {
  // Access JWT payload from context variables
  final userId = c.variables.jwtPayload['sub'];
  return c.json({'userId': userId});
});
```

## Common Patterns

### Public + Protected Routes

`jwt()` runs for every request once registered, no matter where the route
is declared, so leaving routes public means listing them in
`JwtOptions.excludedPaths` rather than registering them before `app.use(jwt())`:

```dart
import 'package:aim_server_jwt/aim_server_jwt.dart';

final app = Aim<JwtVariables>(
  variablesFactory: () => JwtVariables.create(
    JwtOptions(
      algorithm: HS256(
        secretKey: SecretKey(secret: 'your-secret-key-at-least-32-chars'),
      ),
      excludedPaths: ['/login', '/public'],
    ),
  ),
);

// Global middleware
app.use(logger());
app.use(cors());
app.use(jwt());

// Public routes (excluded above, so no token required)
app.post('/login', loginHandler);
app.get('/public', publicHandler);

// Protected routes
app.get('/dashboard', dashboardHandler);
app.get('/profile', profileHandler);
```

### API with Multiple Features

`form()`/`multipart()`/`sse()` aren't middleware — they're extension methods
you call directly in a handler, so they need no `Variables` class of their
own. Only middleware that actually carries per-request state, like JWT,
needs one:

```dart
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_logger/aim_server_logger.dart';
import 'package:aim_server_cors/aim_server_cors.dart';
import 'package:aim_server_jwt/aim_server_jwt.dart';
import 'package:aim_server_form/aim_server_form.dart';

final app = Aim<JwtVariables>(
  variablesFactory: () => JwtVariables.create(
    JwtOptions(
      algorithm: HS256(
        secretKey: SecretKey(secret: Platform.environment['JWT_SECRET']!),
      ),
    ),
  ),
);

app.use(logger());
app.use(cors(CorsOptions(origin: 'https://example.com')));
app.use(jwt());

app.post('/api/data', (c) async {
  final form = await c.req.formData();
  return c.json({'received': form.toMap()});
});
```

### File Upload API

```dart
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_multipart/aim_server_multipart.dart';
import 'package:aim_server_multipart/aim_server_multipart_io.dart';

final app = Aim();

app.use(logger());

app.post('/upload', (c) async {
  final form = await c.req.multipart(maxFileSize: 10 * 1024 * 1024); // 10MB
  final file = form.file('avatar');

  if (file == null) {
    return c.json({'error': 'No file uploaded'}, statusCode: 400);
  }

  await file.saveTo('uploads/${file.filename}');
  return c.json({'uploaded': file.filename});
});
```

## Creating Custom Middleware

You can create your own middleware:

```dart
// Simple middleware
Future<void> requestTiming(Context c, Next next) async {
  final stopwatch = Stopwatch()..start();
  await next();
  stopwatch.stop();
  print('Request took ${stopwatch.elapsedMilliseconds}ms');
}

// Middleware factory
Middleware<E> customHeader<E extends Variables>(String name, String value) {
  return (c, next) async {
    c.header(name, value);
    return next();
  };
}

// Usage
app.use(requestTiming);
app.use(customHeader('X-API-Version', '1.0'));
```

## Middleware Packages

Explore each middleware package for detailed documentation:

- **[CORS](/server/middleware/cors)** - Handle cross-origin requests
- **[Cookie](/server/middleware/cookie)** - Secure cookie management
- **[Form](/server/middleware/form)** - Parse form data
- **[Multipart](/server/middleware/multipart)** - File upload handling
- **[Static Files](/server/middleware/static)** - Serve static assets
- **[Logger](/server/middleware/logger)** - Request/response logging
- **[SSE](/server/middleware/sse)** - Real-time server-sent events
- **[JWT Auth](/server/auth/jwt)** - Token-based authentication
- **[Basic Auth](/server/auth/basic-auth)** - Username/password authentication

## Next Steps

- Learn about [creating custom middleware](/server/concepts/middleware)
- Explore specific middleware packages
- Check out the [Context API](/server/concepts/context) for request handling
