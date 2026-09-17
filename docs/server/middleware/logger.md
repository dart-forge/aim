---
title: Logger Middleware - Aim Framework
description: HTTP request and response logging for Dart. Custom logging callbacks, performance tracking, and JSON logging support.
head:
  - - meta
    - name: keywords
      content: Dart HTTP logging, request logging, response logging, performance monitoring, Aim logger middleware
---

# Logger

HTTP request/response logging middleware.

## Installation

```bash
dart pub add aim_server_logger
```

## Quick Start

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_logger/aim_server_logger.dart';

void main() async {
  final app = Aim();

  // Add logger middleware
  app.use(logger());

  app.get('/', (c) async => c.text('Hello!'));

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
}
```

Output:
```
<-- GET /
--> GET / 200 2ms
```

## Log Format

The default format includes:

- Request direction (`<--`)
- HTTP method (`GET`, `POST`, etc.)
- Request path
- Response direction (`-->`)
- Status code
- Response time in milliseconds

```
<-- POST /api/users
--> POST /api/users 201 15ms
```

## Custom Logging

Customize the log output with `onRequest` and `onResponse` callbacks:

```dart
app.use(logger(
  onResponse: (c, durationMs) async {
    print('[${c.req.method}] ${c.req.path} -> ${c.response?.statusCode} (${durationMs}ms)');
  },
));
```

Output:
```
[GET] / -> 200 (2ms)
[POST] /api/users -> 201 (15ms)
```

## Complete Example

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_logger/aim_server_logger.dart';

void main() async {
  final app = Aim();

  // Add logger with custom format
  app.use(logger(
    onResponse: (c, durationMs) async {
      final timestamp = DateTime.now().toIso8601String();
      print('[$timestamp] ${c.req.method} ${c.req.path} ${c.response?.statusCode} ${durationMs}ms');
    },
  ));

  app.get('/', (c) async {
    return c.json({'message': 'Hello!'});
  });

  app.post('/users', (c) async {
    final body = await c.req.json();
    await Future.delayed(Duration(milliseconds: 50)); // Simulate work
    return c.json({'created': body}, statusCode: 201);
  });

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
  print('Server running on http://localhost:8080');
}
```

Output:
```
[2024-01-01T12:00:00.000Z] GET / 200 2ms
[2024-01-01T12:00:05.000Z] POST /users 201 52ms
```

## Use Cases

### Development Debugging

```dart
app.use(logger()); // See all requests during development
```

### Production Monitoring

```dart
app.use(logger(
  onResponse: (c, durationMs) async {
    if ((c.response?.statusCode ?? 0) >= 400) {
      print('ERROR: ${c.req.method} ${c.req.path} ${c.response?.statusCode} ${durationMs}ms');
    }
    // Successful requests are simply not printed.
  },
));
```

### Performance Tracking

```dart
app.use(logger(
  onResponse: (c, durationMs) async {
    if (durationMs > 1000) {
      print('SLOW: ${c.req.method} ${c.req.path} took ${durationMs}ms');
    }
    print('${c.req.method} ${c.req.path} ${c.response?.statusCode} ${durationMs}ms');
  },
));
```

### JSON Logging

```dart
import 'dart:convert';

app.use(logger(
  onResponse: (c, durationMs) async {
    final log = {
      'timestamp': DateTime.now().toIso8601String(),
      'method': c.req.method,
      'path': c.req.path,
      'status': c.response?.statusCode,
      'duration_ms': durationMs,
    };
    print(jsonEncode(log));
  },
));
```

Output:
```json
{"timestamp":"2024-01-01T12:00:00.000Z","method":"GET","path":"/","status":200,"duration_ms":2}
```

## Best Practices

1. **Place logger first** - Capture all requests
   ```dart
   app.use(logger()); // First middleware
   app.use(cors());
   app.use(jwt());
   ```

2. **Custom format for production** - Include timestamps and metadata
   ```dart
   app.use(logger(
     onResponse: (c, durationMs) async {
       print('[${DateTime.now()}] ${c.req.method} ${c.req.path} ${c.response?.statusCode} ${durationMs}ms');
     },
   ));
   ```

3. **Conditional logging** - Log only errors or slow requests
   ```dart
   onResponse: (c, durationMs) async {
     if ((c.response?.statusCode ?? 0) >= 500 || durationMs > 5000) {
       print('ALERT: ${c.req.method} ${c.req.path} ${c.response?.statusCode} ${durationMs}ms');
     }
     // Normal requests are simply not printed.
   },
   ```

4. **Structured logging** - Use JSON for log aggregation
   ```dart
   onResponse: (c, durationMs) async {
     print(jsonEncode({
       'level': (c.response?.statusCode ?? 0) >= 500 ? 'error' : 'info',
       'method': c.req.method,
       'path': c.req.path,
       'status': c.response?.statusCode,
       'duration': durationMs,
     }));
   },
   ```

## Next Steps

- Learn about [Middleware patterns](/server/concepts/middleware)
- Explore [Error handling](/server/concepts/middleware#error-handling)
- Read about [Performance monitoring](/server/concepts/context#performance)
