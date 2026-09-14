## 0.2.0

- **Breaking:** follows `aim_core`'s rename of `Env` → `Variables` and `envFactory` → `variablesFactory` (re-exported).
- Internals moved to the new `aim_core` package. `aim_server` re-exports it, so existing imports keep working.
- `serve()` is now an extension on `Aim` provided by `aim_server`.
- **Breaking:** `Request.raw` is typed `Object?`. Use the `Request.httpRequest` extension getter from `aim_server` to get the `HttpRequest`.
- Unhandled errors without `onError` are still printed with their stack trace when running via `serve()`. `Aim.handle()` itself no longer prints.

## 0.1.1

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.1.1)


## 0.1.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/v0.1.0)


## 0.0.6

### Enhancements
- **Real-time SSE streaming support**: Automatically disables buffering for Server-Sent Events (SSE) responses
  - Detects `Content-Type: text/event-stream` and sets `bufferOutput = false` on the underlying `HttpResponse`
  - Enables real-time event streaming without buffering delays
  - Non-SSE responses continue to use buffering for optimal performance
- **Streaming integration tests**: Added comprehensive integration tests for SSE streaming behavior
  - Validates real-time event delivery with timestamp verification
  - Ensures buffering behavior is correct for both SSE and non-SSE responses

### Technical Details
The server now automatically optimizes response buffering based on content type:
- SSE responses (`text/event-stream`): Buffering disabled for real-time streaming
- Other responses: Buffering enabled for performance

This change is backward compatible and requires no code changes from users.

## 0.0.5

### New Features
- **Public `handle(Request)` method**: Added a new public API for handling requests without the HTTP layer
  - Enables testing Aim applications without starting an actual HTTP server
  - Executes the full request handling logic: routing, middleware, handlers, and error handling
  - Primarily designed for use with `aim_server_testing` package

### Use Case
```dart
final app = Aim();
app.get('/users/:id', (c) => c.json({'id': c.param('id')}));

final request = Request('GET', Uri.parse('http://localhost/users/123'));
final response = await app.handle(request);
// response.statusCode == 200
```

This new API simplifies testing and allows for direct request processing in scenarios where the HTTP layer is not needed.

## 0.0.4
Fix README.md and pubspec description

## 0.0.3
### Breaking Changes
- **CORS middleware removed**: CORS functionality has been extracted to the `aim_server_cors` package
- If you need CORS support, add the `aim_server_cors` package to your dependencies

### Migration
Before:
```dart
import 'package:aim_server/aim_server.dart';

final app = Aim();
app.use(cors());
```

After:
```dart
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_cors/aim_server_cors.dart';

final app = Aim();
app.use(cors());
```

pubspec.yaml:
```yaml
dependencies:
  aim_server: ^0.1.0
  aim_server_cors: ^0.0.1
```

## 0.0.2
### Fixes
Fix README.md

## 0.0.1

Initial release of aim_server - A lightweight and fast web server framework for Dart.

### Features

- HTTP Server: Built on Dart's native HTTP server with minimal overhead
- Routing:
  - Path-based routing with support for GET, POST, PUT, DELETE methods
  - Path parameters (e.g., `/users/:id`)
  - Query parameter support
- Middleware: Composable middleware chain for request/response processing
- Request/Response Handling:
  - JSON request/response support
  - Text and HTML responses
  - Redirect support
  - Custom status codes
- CORS: Built-in Cross-Origin Resource Sharing support
- Error Handling:
  - Custom 404 handler
  - Global error handler
- Environment Variables: Built-in environment variable support with the `Env` class
- Type Safety: Full Dart type safety throughout the API

### Supported

- Dart SDK: `^3.10.0`
- Platforms: All platforms supported by Dart (Linux, macOS, Windows)

### What's Included

- Core `Aim` application class
- `Context` for request handling
- `Request` and `Response` abstractions
- `Body` for request body handling
- `Message` for HTTP message handling
- CORS middleware utilities
- Environment variable utilities
