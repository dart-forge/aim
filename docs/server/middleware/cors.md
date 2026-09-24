---
title: CORS Middleware - Aim Framework
description: Handle cross-origin requests in Dart. Configure origins, credentials, headers, and preflight caching for secure API development.
head:
  - - meta
    - name: keywords
      content: Dart CORS, cross-origin, preflight, Access-Control-Allow-Origin, Aim CORS middleware
---

# CORS

Cross-Origin Resource Sharing (CORS) middleware for handling cross-origin HTTP requests.

## Installation

```bash
dart pub add aim_server_cors
```

## Quick Start

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_cors/aim_server_cors.dart';

void main() async {
  final app = Aim();

  // Enable CORS for all origins
  app.use(cors());

  app.get('/api/data', (c) async {
    return c.json({'message': 'CORS enabled'});
  });

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
}
```

## Configuration

### Allow All Origins

Default configuration allows all origins:

```dart
app.use(cors());
// Access-Control-Allow-Origin: *
```

### Specific Origin

Allow requests from a specific origin:

```dart
app.use(cors(CorsOptions(
  origin: 'https://example.com',
  credentials: true,
)));
```

### Multiple Origins

Allow multiple specific origins:

```dart
app.use(cors(CorsOptions(
  origin: [
    'https://example.com',
    'https://app.example.com',
    'https://admin.example.com',
  ],
  credentials: true,
)));
```

### Custom Origin Validation

Use a function to dynamically validate origins:

```dart
app.use(cors(CorsOptions(
  origin: (String origin) {
    // Allow all subdomains of example.com
    return origin.endsWith('.example.com');
  },
  credentials: true,
)));
```

## Allowed Methods

Specify which HTTP methods are allowed:

```dart
app.use(cors(CorsOptions(
  allowMethods: ['GET', 'POST', 'PUT', 'DELETE'],
)));
```

Default: `['GET', 'HEAD', 'PUT', 'POST', 'DELETE', 'PATCH']`

## Allowed Headers

Control which headers can be used in requests:

```dart
app.use(cors(CorsOptions(
  allowHeaders: ['Content-Type', 'Authorization', 'X-Custom-Header'],
)));
```

Default: `['*']` (any header is allowed)

## Exposed Headers

Specify which headers the browser can access:

```dart
app.use(cors(CorsOptions(
  exposeHeaders: ['X-Request-ID', 'X-Response-Time'],
)));
```

## Credentials

Enable cookies and authorization headers across origins:

```dart
app.use(cors(CorsOptions(
  origin: 'https://example.com',
  credentials: true,
)));
```

::: warning
When `credentials: true`, you cannot use `origin: '*'`. You must specify exact origin(s).
:::

## Preflight Caching

Control how long browsers cache preflight responses. `maxAge` is `int?`
seconds, not a `Duration`:

```dart
app.use(cors(CorsOptions(
  maxAge: 86400, // 24 hours, in seconds
)));
```

Default: `null` (no `Access-Control-Max-Age` header is sent)

## Complete Example

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_cors/aim_server_cors.dart';

void main() async {
  final app = Aim();

  // Production CORS configuration
  app.use(cors(CorsOptions(
    origin: [
      'https://example.com',
      'https://app.example.com',
    ],
    credentials: true,
    allowMethods: ['GET', 'POST', 'PUT', 'DELETE'],
    allowHeaders: ['Content-Type', 'Authorization'],
    exposeHeaders: ['X-Request-ID'],
    maxAge: 86400,
  )));

  // API routes
  app.get('/api/users', (c) async {
    return c.json({'users': []});
  });

  app.post('/api/users', (c) async {
    final body = await c.req.json();
    return c.json({'created': body}, statusCode: 201);
  });

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
  print('API server running on http://localhost:8080');
}
```

## How It Works

### Simple Requests

For simple requests (GET, HEAD, POST with basic headers), the middleware adds:

```
Access-Control-Allow-Origin: https://example.com
Access-Control-Allow-Credentials: true
```

### Preflight Requests

For complex requests (custom headers, methods like PUT/DELETE), browsers send an OPTIONS preflight request first. The middleware responds with:

```
Access-Control-Allow-Origin: https://example.com
Access-Control-Allow-Methods: GET, POST, PUT, DELETE
Access-Control-Allow-Headers: Content-Type, Authorization
Access-Control-Max-Age: 86400
```

## Security Best Practices

1. **Never use `*` with credentials in production**
   ```dart
   // ❌ Bad
   app.use(cors(CorsOptions(
     origin: '*',
     credentials: true, // Browsers will reject this
   )));

   // ✅ Good
   app.use(cors(CorsOptions(
     origin: 'https://example.com',
     credentials: true,
   )));
   ```

2. **Validate origins carefully**
   ```dart
   // ❌ Bad - Too permissive
   origin: (String origin) => true,

   // ✅ Good - Specific validation
   origin: (String origin) {
     return origin.endsWith('.example.com') ||
            origin == 'https://example.com';
   },
   ```

3. **Limit allowed methods**
   ```dart
   // Only allow necessary methods
   app.use(cors(CorsOptions(
     allowMethods: ['GET', 'POST'], // Don't allow DELETE if not needed
   )));
   ```

## Development vs Production

### Development

```dart
// Permissive for local development
app.use(cors());
```

### Production

```dart
// Strict configuration
app.use(cors(CorsOptions(
  origin: Platform.environment['ALLOWED_ORIGINS']?.split(',') ?? [],
  credentials: true,
  allowMethods: ['GET', 'POST', 'PUT', 'DELETE'],
  allowHeaders: ['Content-Type', 'Authorization'],
  maxAge: 86400,
)));
```

## CorsOptions Reference

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `origin` | `dynamic` (`String`, `List<String>`, or `bool Function(String)`) | `'*'` | Allowed origin(s) |
| `credentials` | `bool` | `false` | Allow credentials |
| `allowMethods` | `List<String>` | `['GET', 'HEAD', 'PUT', 'POST', 'DELETE', 'PATCH']` | Allowed HTTP methods |
| `allowHeaders` | `List<String>` | `['*']` | Allowed request headers |
| `exposeHeaders` | `List<String>` | `[]` | Exposed response headers |
| `maxAge` | `int?` (seconds) | `null` | Preflight cache duration |

## Common Issues

### CORS error with credentials

**Problem**: Browser blocks request even though CORS is configured.

**Solution**: Make sure `origin` is not `'*'` when `credentials: true`:

```dart
app.use(cors(CorsOptions(
  origin: 'https://example.com', // Specific origin required
  credentials: true,
)));
```

### Custom headers not working

**Problem**: Browser rejects custom headers like `X-API-Key`.

**Solution**: Add them to `allowHeaders`:

```dart
app.use(cors(CorsOptions(
  allowHeaders: ['Content-Type', 'X-API-Key'],
)));
```

## Next Steps

- Learn about [JWT Authentication](/server/auth/jwt) for secure APIs
- Explore [Logger](/server/middleware/logger) to debug CORS issues
- Read about [Middleware](/server/concepts/middleware) patterns
