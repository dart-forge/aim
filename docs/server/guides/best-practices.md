---
title: Best Practices - Aim Framework
description: Production-ready Dart server guidelines. Project structure, error handling, security, performance, logging, and deployment tips.
head:
  - - meta
    - name: keywords
      content: Dart best practices, production deployment, error handling, security, performance, Aim best practices
---

# Best Practices

Guidelines and recommendations for building production-ready Aim applications.

## Project Structure

### Recommended Layout

```
my_app/
├── bin/
│   └── server.dart          # Entry point
├── lib/
│   ├── routes/              # Route handlers
│   │   ├── users.dart
│   │   └── posts.dart
│   ├── middleware/          # Custom middleware
│   │   └── auth.dart
│   ├── models/              # Data models
│   │   └── user.dart
│   ├── services/            # Business logic
│   │   └── user_service.dart
│   └── variables.dart               # Variables classes
├── test/                    # Tests
│   ├── routes/
│   └── middleware/
└── pubspec.yaml
```

### Separate Routes

```dart
// lib/routes/users.dart
import 'package:aim_server/aim_server.dart';

void registerUserRoutes(Aim app) {
  app.get('/users', getAllUsers);
  app.get('/users/:id', getUserById);
  app.post('/users', createUser);
  app.put('/users/:id', updateUser);
  app.delete('/users/:id', deleteUser);
}

Future<Response> getAllUsers(Context c) async {
  // Implementation
  return c.json({'users': []});
}
```

```dart
// bin/server.dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:my_app/routes/users.dart';

void main() async {
  final app = Aim();

  registerUserRoutes(app);

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
}
```

## Error Handling

### Global Error Handler

```dart
Future<void> errorHandler(Context c, Next next) async {
  try {
    await next();
  } catch (error, stackTrace) {
    print('Error: $error');
    print('Stack: $stackTrace');

    // Don't expose internal errors in production
    final message = Platform.environment['ENV'] == 'production'
        ? 'Internal Server Error'
        : error.toString();

    c.json({
      'error': message,
    }, statusCode: 500);
  }
}

void main() async {
  final app = Aim();

  // Add error handler first
  app.use(errorHandler);

  // Your routes...
}
```

### Validation

```dart
app.post('/users', (c) async {
  final body = await c.req.json();

  // Validate required fields
  if (body['email'] == null || body['email'].isEmpty) {
    return c.json(
      {'error': 'Email is required'},
      statusCode: 400,
    );
  }

  if (!isValidEmail(body['email'])) {
    return c.json(
      {'error': 'Invalid email format'},
      statusCode: 400,
    );
  }

  // Process request...
});
```

## Security

### Use Environment Variables

```dart
// ❌ Bad - Hardcoded secrets
final secret = 'my-secret-key';

// ✅ Good - Environment variables
final secret = Platform.environment['JWT_SECRET'] ??
               (throw Exception('JWT_SECRET not set'));
```

### HTTPS in Production

```dart
void main() async {
  final app = Aim();

  if (Platform.environment['ENV'] == 'production') {
    // Use HTTPS
    final context = SecurityContext()
      ..useCertificateChain('server_chain.pem')
      ..usePrivateKey('server_key.pem');

    await app.serve(
      host: InternetAddress.anyIPv4,
      port: 443,
      securityContext: context,
    );
  } else {
    // Development
    await app.serve(host: InternetAddress.anyIPv4, port: 8080);
  }
}
```

### Input Sanitization

```dart
import 'dart:convert';

app.post('/comments', (c) async {
  final body = await c.req.json();
  final comment = body['comment'];

  // Validate/reject unexpected input before it reaches storage or another
  // system, rather than trying to "clean" it in place.
  if (comment is! String || comment.isEmpty) {
    return c.json({'error': 'comment is required'}, statusCode: 400);
  }

  // Store the raw, validated value — use parameterized queries (as
  // `aim_postgres` and the ORM already do) so it can never be interpreted
  // as SQL.
  await db.execute(
    'INSERT INTO comments (content) VALUES (:content)',
    params: {'content': comment},
  );

  return c.json({'created': true}, statusCode: 201);
});
```

Sanitization is not one step. Keep the three concerns separate:
- **Input validation** — reject or normalize input that doesn't match what
  you expect (shown above).
- **Parameterized queries** — never build SQL by concatenating user input;
  pass values as parameters, as above.
- **Contextual output encoding** — escape for the context the value is
  rendered into (`HtmlEscape().convert(...)` for HTML *output*, a different
  encoder for a URL or a JSON string embedded in `<script>`). Escaping once
  at write time and storing the escaped string bakes in a decision that may
  be wrong for a different consumer (an API client, a different template)
  later; encode at render time for the context you're rendering into.

### Rate Limiting

This is a local sketch, not a production rate limiter: `x-forwarded-for`
is client-supplied and easy to spoof unless your proxy overwrites it and
strips any value it received from the client first, the in-process `Map`
does not share state across multiple server instances, it resets on every
restart, and nothing bounds its size (a limiter serving many distinct IPs
without cleanup grows unbounded). A real deployment behind a proxy needs
the proxy's trusted client-IP header and out-of-process storage (such as
Redis) shared across instances.

```dart
final requests = <String, List<DateTime>>{};

Middleware<E> ratelimit<E extends Variables>({
  required int maxRequests,
  required Duration window,
}) {
  return (c, next) async {
    final ip = c.req.headers['x-forwarded-for'] ?? 'unknown';
    final now = DateTime.now();

    requests[ip] ??= [];
    requests[ip]!.removeWhere((t) => now.difference(t) > window);

    if (requests[ip]!.length >= maxRequests) {
      c.json(
        {'error': 'Rate limit exceeded'},
        statusCode: 429,
      );
      return;
    }

    requests[ip]!.add(now);
    return next();
  };
}

// Usage
app.use(ratelimit(maxRequests: 100, window: Duration(minutes: 1)));
```

## Performance

### Connection Pooling

`PostgresDatabase` (`aim_postgres`) already *is* a connection pool — there
is no separate pool class to reach for:

```dart
// ❌ Bad - A new pool (and new connections) per request
app.get('/users', (c) async {
  final db = await PostgresDatabase.connect(dbUrl);
  final users = await db.query('SELECT * FROM users');
  await db.close();
  return c.json({'users': users});
});

// ✅ Good - Create the pool once, at startup, and reuse it
final db = await PostgresDatabase.connect(dbUrl, maxConnections: 10);

app.get('/users', (c) async {
  final users = await db.query('SELECT * FROM users');
  return c.json({'users': users});
});
```

`connect()` also takes `acquireTimeout`, `idleTimeout`, `maxLifetime`, and
`validationInterval` `Duration`s to tune pool behavior; see the
[PostgreSQL driver page](/database/drivers/postgres) for what each one
does. Call `db.close()` once, during shutdown (see
[Graceful Shutdown](#graceful-shutdown) below) — not per request.

### Caching

```dart
final cache = <String, dynamic>{};

app.get('/expensive', (c) async {
  final cacheKey = 'expensive_data';

  // Check cache
  if (cache.containsKey(cacheKey)) {
    c.header('X-Cache', 'HIT');
    return c.json(cache[cacheKey]);
  }

  // Compute expensive data
  final data = await computeExpensiveData();

  // Cache for 5 minutes
  cache[cacheKey] = data;
  Timer(Duration(minutes: 5), () => cache.remove(cacheKey));

  c.header('X-Cache', 'MISS');
  return c.json(data);
});
```

### Async Operations

```dart
// ✅ Good - Concurrent operations
app.get('/dashboard', (c) async {
  final results = await Future.wait([
    fetchUserData(userId),
    fetchUserPosts(userId),
    fetchUserComments(userId),
  ]);

  return c.json({
    'user': results[0],
    'posts': results[1],
    'comments': results[2],
  });
});
```

## Logging

### Structured Logging

```dart
import 'dart:convert';

void logRequest(Context c, int statusCode, int duration) {
  final log = {
    'timestamp': DateTime.now().toIso8601String(),
    'method': c.req.method,
    'path': c.req.path,
    'status': statusCode,
    'duration_ms': duration,
    'user_agent': c.req.headers['user-agent'],
  };

  print(jsonEncode(log));
}

app.use((c, next) async {
  final stopwatch = Stopwatch()..start();
  await next();
  stopwatch.stop();
  logRequest(c, 200, stopwatch.elapsedMilliseconds);
});
```

### Log Levels

```dart
enum LogLevel { debug, info, warn, error }

void log(LogLevel level, String message, [Map<String, dynamic>? meta]) {
  if (Platform.environment['LOG_LEVEL'] == 'error' &&
      level != LogLevel.error) {
    return; // Skip non-error logs in production
  }

  final log = {
    'level': level.name,
    'message': message,
    'timestamp': DateTime.now().toIso8601String(),
    if (meta != null) 'meta': meta,
  };

  print(jsonEncode(log));
}
```

## Testing

### Test Coverage

```bash
# Run tests with coverage
dart test --coverage=coverage

# Generate HTML report
dart install coverage
format_coverage --lcov --in=coverage --out=coverage/lcov.info

genhtml coverage/lcov.info -o coverage/html
```

### Integration Tests

```dart
test('Complete user flow', () async {
  final app = Aim();
  // Configure app...

  final client = TestClient(app);

  // 1. Register
  final registerRes = await client.post('/register', body: {
    'email': 'test@example.com',
    'password': 'password123',
  });
  expect(registerRes.statusCode, equals(201));

  // 2. Login
  final loginRes = await client.post('/login', body: {
    'email': 'test@example.com',
    'password': 'password123',
  });
  final token = (await loginRes.bodyAsJson())['token'];

  // 3. Access protected route
  final profileRes = await client.get(
    '/profile',
    headers: {'Authorization': 'Bearer $token'},
  );
  expect(profileRes.statusCode, equals(200));
});
```

## Deployment

### Building for Production

Use the Aim CLI to compile your application:

```bash
# Build with default settings (output: build/server)
aim build

# Custom entry point and output
aim build --entry bin/server.dart --output my-server
```

The build command:
- Compiles your Dart code to a native executable
- Reads configuration from `pubspec.yaml` (`aim.entry`)
- Outputs to `build/server` by default

### Environment-Based Config

```dart
class Config {
  static final port = int.parse(
    Platform.environment['PORT'] ?? '8080',
  );

  static final dbUrl = Platform.environment['DATABASE_URL'] ??
                       (throw Exception('DATABASE_URL not set'));

  static final jwtSecret = Platform.environment['JWT_SECRET'] ??
                           (throw Exception('JWT_SECRET not set'));

  static final isProduction = Platform.environment['ENV'] == 'production';
}

void main() async {
  final app = Aim();

  if (Config.isProduction) {
    // Production settings — `secureHeaders()` isn't a real middleware;
    // set security headers yourself, e.g. with a small custom middleware
    // or `aim_server_cors`'s options where they overlap.
    app.use((c, next) async {
      c.header('X-Content-Type-Options', 'nosniff');
      c.header('X-Frame-Options', 'DENY');
      return next();
    });
  } else {
    // Development settings — use the real logger middleware
    app.use(logger());
  }

  await app.serve(host: InternetAddress.anyIPv4, port: Config.port);
}
```

### Health Checks

```dart
app.get('/health', (c) async {
  final health = {
    'status': 'ok',
    'timestamp': DateTime.now().toIso8601String(),
    'uptime': DateTime.now().difference(startTime).inSeconds,
  };

  // Check database — there is no `ping()` on `PostgresDatabase`; a plain
  // query is the health-check idiom.
  try {
    await db.query('SELECT 1');
    health['database'] = 'ok';
  } catch (e) {
    health['database'] = 'error';
    health['status'] = 'degraded';
  }

  final statusCode = health['status'] == 'ok' ? 200 : 503;
  return c.json(health, statusCode: statusCode);
});
```

### Graceful Shutdown

```dart
void main() async {
  final app = Aim();

  final server = await app.serve(host: InternetAddress.anyIPv4, port: 8080);

  // Handle shutdown signals
  ProcessSignal.sigterm.watch().listen((signal) async {
    print('Received SIGTERM, shutting down...');

    // Close database connections
    await db.close();

    // Stop accepting new connections
    await server.close();

    exit(0);
  });
}
```

## Next Steps

- Read about [Testing](/server/guides/testing)
- Check out the [FAQ](/server/guides/faq)
- Explore [Middleware](/server/middleware/)
