---
title: FAQ - Aim Framework
description: Frequently asked questions about Aim. Installation, routing, middleware, authentication, deployment, and troubleshooting.
head:
  - - meta
    - name: keywords
      content: Aim FAQ, Dart framework questions, installation help, troubleshooting, Aim support
---

# FAQ

Frequently asked questions about Aim.

## General

### What is Aim?

Aim is a lightweight, fast web framework for Dart. It's designed to be simple, type-safe, and performance-focused, with an API inspired by modern frameworks like Hono.

### Why Aim over other Dart frameworks?

- **Simple API**: Context-based API that's easy to learn
- **Type-Safe**: Leverages Dart's type system with custom `Variables` classes for context variables
- **Modular**: Rich ecosystem of optional middleware packages
- **Performance**: Minimal overhead with optimized routing
- **Great DX**: Built-in hot reload and comprehensive testing utilities

### Is Aim production-ready?

Yes! Aim is stable and suitable for production use. The framework follows semantic versioning and has comprehensive test coverage.

### What's the relationship with Hono?

Aim's API is inspired by [Hono](https://hono.dev/), a popular JavaScript framework. While the API design is similar, Aim is built from the ground up for Dart with its own implementation.

## Installation & Setup

### What Dart version do I need?

Aim requires Dart SDK 3.10.0 or higher.

### How do I install Aim?

```bash
# Using CLI (recommended)
dart install aim_cli
aim create my_app

# Manual
dart pub add aim_server
```

See the [Installation guide](/server/installation) for details.

### How do I update to the latest version?

```bash
dart pub upgrade aim_server
```

Or update your `pubspec.yaml` to the latest version.

## Routing

### How do I define routes?

```dart
app.get('/users', handler);
app.post('/users', handler);
app.put('/users/:id', handler);
app.delete('/users/:id', handler);
```

See [Routing](/server/concepts/routing) for details.

### How do I use path parameters?

```dart
app.get('/users/:id', (c) async {
  final id = c.param('id');
  return c.json({'userId': id});
});
```

### How do I handle query parameters?

```dart
app.get('/search', (c) async {
  final query = c.req.queries['q']?.first;
  return c.json({'query': query});
});
```

### Can I use wildcards?

Yes:

```dart
app.get('/api/*', handler);   // Match /api/anything
app.notFound(notFoundHandler);  // Not found
```

## Middleware

### What middleware is available?

Official middleware packages:
- [CORS](/server/middleware/cors)
- [Cookie](/server/middleware/cookie)
- [Form](/server/middleware/form)
- [Multipart](/server/middleware/multipart)
- [Static Files](/server/middleware/static)
- [Logger](/server/middleware/logger)
- [SSE](/server/middleware/sse)
- [JWT Auth](/server/auth/jwt)
- [Basic Auth](/server/auth/basic-auth)

See [Middleware Overview](/server/middleware/) for all packages.

### How do I create custom middleware?

```dart
Future<void> myMiddleware(Context c, Next next) async {
  // Before handler
  print('Before');

  await next();

  // After handler
  print('After');
}

app.use(myMiddleware);
```

See [Middleware guide](/server/concepts/middleware) for details.

### How do I skip middleware for specific routes?

```dart
app.use((c, next) async {
  if (c.req.path == '/public') {
    return next();
  }
  // Apply middleware logic
});
```

Or use path exclusion (available in some middleware):

```dart
JwtOptions(
  excludedPaths: ['/login', '/register'],
)
```

## Request & Response

### How do I read JSON body?

```dart
app.post('/users', (c) async {
  final body = await c.req.json();
  final name = body['name'];
  return c.json({'created': name});
});
```

### How do I send JSON response?

```dart
return c.json({'message': 'Hello'});
return c.json({'error': 'Not found'}, statusCode: 404);
```

### How do I handle file uploads?

Use the [Multipart middleware](/server/middleware/multipart) — `multipart()`
is an extension method on `Request`, not a middleware:

```dart
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_multipart/aim_server_multipart.dart';
import 'package:aim_server_multipart/aim_server_multipart_io.dart';

app.post('/upload', (c) async {
  final form = await c.req.multipart();
  final file = form.file('document');

  if (file == null) {
    return c.json({'error': 'No file uploaded'}, statusCode: 400);
  }

  await file.saveTo('uploads/${file.filename}');
  return c.json({'uploaded': file.filename});
});
```

### How do I set response headers?

```dart
app.get('/', (c) async {
  c.header('X-Custom', 'value');
  c.header('Cache-Control', 'no-cache');
  return c.json({'data': 'value'});
});
```

## Authentication

### How do I implement authentication?

Use [JWT Auth](/server/auth/jwt) or [Basic Auth](/server/auth/basic-auth):

```dart
import 'package:aim_server_jwt/aim_server_jwt.dart';

final app = Aim<JwtVariables>(
  variablesFactory: () => JwtVariables.create(
    JwtOptions(
      algorithm: HS256(
        secretKey: SecretKey(secret: 'your-secret-key'),
      ),
      excludedPaths: ['/login'],
    ),
  ),
);

app.use(jwt());
```

### How do I protect specific routes?

Apply middleware before the routes you want to protect:

```dart
// Public routes
app.post('/login', loginHandler);

// Protected routes (apply auth middleware)
app.use(jwt());
app.get('/dashboard', dashboardHandler);
```

### Can I use session-based auth?

Yes, use the [Cookie extensions](/server/middleware/cookie):

```dart
import 'package:aim_server_cookie/aim_server_cookie.dart';

app.post('/login', (c) async {
  c.setCookie(
    'session_id',
    sessionId,
    options: CookieOptions(
      httpOnly: true,
      secure: true,
      maxAge: Duration(days: 7),
    ),
  );
  return c.json({'success': true});
});
```

## Development

### How do I enable hot reload?

Use the Aim CLI:

```bash
aim dev
```

### How do I debug my application?

Use Dart's built-in debugger with VS Code or IntelliJ:

1. Set breakpoints in your code
2. Run with debugger (F5 in VS Code)
3. Use the debug console

For logging, use the [Logger middleware](/server/middleware/logger).

### How do I run tests?

```bash
dart test
```

See the [Testing guide](/server/guides/testing) for details.

## Deployment

### How do I deploy to production?

1. Build your application:
   ```bash
   # Build with default settings (output: build/server)
   aim build

   # Custom entry point and output
   aim build --entry bin/server.dart --output my-server
   ```

2. Deploy the binary to your server

3. Run with environment variables:
   ```bash
   ENV=production JWT_SECRET=xxx ./build/server
   ```

### Does Aim support serverless?

Aim is designed for traditional server deployments. For serverless, consider using `shelf` with Dart's Cloud Functions.

### How do I enable HTTPS?

```dart
final context = SecurityContext()
  ..useCertificateChain('server_chain.pem')
  ..usePrivateKey('server_key.pem');

await app.serve(
  host: InternetAddress.anyIPv4,
  port: 443,
  securityContext: context,
);
```

### How do I configure CORS for production?

```dart
import 'package:aim_server_cors/aim_server_cors.dart';

app.use(cors(CorsOptions(
  origin: ['https://example.com', 'https://app.example.com'],
  credentials: true,
  allowMethods: ['GET', 'POST', 'PUT', 'DELETE'],
)));
```

See [CORS guide](/server/middleware/cors) for details.

## Performance

### How fast is Aim?

Aim is designed for performance with minimal overhead. Benchmarks show comparable or better performance than other Dart frameworks.

### How do I optimize performance?

- Use connection pooling for databases
- Implement caching where appropriate
- Use async operations efficiently
- Profile with Dart DevTools

See [Best Practices](/server/guides/best-practices) for optimization tips.

### Can I use multiple isolates?

Yes, you can run multiple instances across isolates:

```dart
void main() async {
  final cores = Platform.numberOfProcessors;

  for (var i = 0; i < cores; i++) {
    await Isolate.spawn(startServer, i);
  }
}

void startServer(int id) async {
  final app = Aim();
  // Configure app...
  await app.serve(host: InternetAddress.anyIPv4, port: 8080 + id);
}
```

## Troubleshooting

### My middleware isn't running

Check the order - middleware runs in the order it's added:

```dart
app.use(logger());    // Runs first
app.use(cors());      // Runs second
app.use(jwt());       // Runs third
```

### Headers aren't being set

Make sure you set headers **before** returning the response:

```dart
// ✅ Good
c.header('X-Version', '1.0');
return c.json({...});

// ❌ Bad
const response = c.json({...});
c.header('X-Version', '1.0');  // Too late!
return response;
```

### Port already in use

Another process is using the port. Kill it or use a different port:

```bash
# Find process
lsof -i :8080

# Kill process
kill -9 <PID>

# Or use different port
await app.serve(host: InternetAddress.anyIPv4, port: 3000);
```

## Community

### How do I get help?

- Check this FAQ
- Read the [documentation](/)
- Open an issue on [GitHub](https://github.com/dart-forge/aim/issues)

### How do I contribute?

See the [Contributing Guide](https://github.com/dart-forge/aim/blob/main/CONTRIBUTING.md).

### Where can I report bugs?

Report bugs on [GitHub Issues](https://github.com/dart-forge/aim/issues).

## Next Steps

- Read the [Best Practices](/server/guides/best-practices)
- Explore [Testing](/server/guides/testing)
- Check out [Middleware](/server/middleware/)
