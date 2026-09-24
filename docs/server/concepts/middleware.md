---
title: Middleware - Aim Framework
description: Master middleware patterns in Aim. Learn to create authentication, logging, error handling, and custom middleware for Dart server applications.
head:
  - - meta
    - name: keywords
      content: Dart middleware, authentication middleware, logging middleware, error handling, Dart server, Aim middleware
---

# Middleware

Middleware functions are the building blocks of request processing in Aim. They run before your route handlers and can modify requests, responses, or execute side effects like logging.

## What is Middleware?

A middleware is a function that takes a `Context` and a `Next` function, and returns a `Future<void>`:

```dart
typedef Middleware<E extends Variables> = Future<void> Function(
  Context<E> c,
  Next next,
);
```

- **Context (`c`)**: Provides access to the request and response
- **Next (`next`)**: Calls the next middleware or route handler in the chain

::: warning A middleware cannot return a response
The return type is `Future<void>`, so `return c.json(...)` does not compile: `c.json()`
evaluates to a `Response`. The response helpers (`c.json()`, `c.text()`, ...) finalize the
response on the context, so calling one and returning without calling `next()` is enough
to stop the chain and send it:

```dart
c.json({'error': 'Unauthorized'}, statusCode: 401);
return; // next() is not called - the finalized response is sent
```
:::

## Basic Middleware

Here's a simple logging middleware:

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';

Future<void> simpleLogger(Context c, Next next) async {
  print('<-- ${c.req.method} ${c.req.path}');
  await next();
  print('--> ${c.req.method} ${c.req.path}');
}

void main() async {
  final app = Aim();

  // Use the middleware
  app.use(simpleLogger);

  app.get('/', (c) async => c.text('Hello!'));

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
}
```

## Using Middleware

Add middleware with the `use()` method:

```dart
final app = Aim();

// Global middleware (applies to all routes)
app.use(logger());
app.use(cors());

// Routes
app.get('/', handler);
```

## Middleware Order

Middleware executes in the order it's defined:

```dart
final app = Aim();

app.use((c, next) async {
  print('1. First middleware - before');
  await next();
  print('1. First middleware - after');
});

app.use((c, next) async {
  print('2. Second middleware - before');
  await next();
  print('2. Second middleware - after');
});

app.get('/', (c) async {
  print('3. Route handler');
  return c.text('Hello!');
});

// Output:
// 1. First middleware - before
// 2. Second middleware - before
// 3. Route handler
// 2. Second middleware - after
// 1. First middleware - after
```

## Calling Next

The `next()` function passes control to the next middleware or route handler:

```dart
// ✅ Always call next() if you want the chain to continue
app.use((c, next) async {
  print('Before handler');
  await next();
  print('After handler');
});

// ✅ Return early without calling next() to stop the chain
app.use((c, next) async {
  if (!isAuthorized(c)) {
    c.json({'error': 'Unauthorized'}, statusCode: 401);
    return; // next() is NOT called - chain stops here
  }
  return next();
});
```

## Modifying Context

Middleware can modify the context before passing it forward:

```dart
class MyVariables extends Variables {
  String? requestId;
  String? userId;
}

void main() async {
  final app = Aim<MyVariables>(
    variablesFactory: () => MyVariables(),
  );

  // Add request ID
  app.use((c, next) async {
    c.variables.requestId = DateTime.now().millisecondsSinceEpoch.toString();
    return next();
  });

  // Add user ID from header
  app.use((c, next) async {
    final userId = c.req.headers['x-user-id'];
    c.variables.userId = userId;
    return next();
  });

  app.get('/', (c) async {
    return c.json({
      'requestId': c.variables.requestId,
      'userId': c.variables.userId,
    });
  });

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
}
```

## Setting Response Headers

Set headers that will be included in the final response:

```dart
app.use((c, next) async {
  c.header('X-Request-ID', generateId());
  c.header('X-Powered-By', 'Aim');
  return next();
});
```

## Error Handling Middleware

Catch and handle errors in a centralized way:

```dart
Future<void> errorHandler(Context c, Next next) async {
  try {
    await next();
  } catch (error, stackTrace) {
    print('Error: $error');
    print('Stack: $stackTrace');

    c.json({
      'error': 'Internal Server Error',
      'message': error.toString(),
    }, statusCode: 500);
  }
}

void main() async {
  final app = Aim();

  // Add error handler first
  app.use(errorHandler);

  app.get('/error', (c) async {
    throw Exception('Something went wrong!');
  });

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
}
```

### `app.onError`

A try/catch middleware only catches errors thrown while `next()` runs — it
still has to be registered before every route that can throw. `Aim` also
has a single, centralized hook:

```dart
typedef ErrorHandler<E extends Variables> = Future<Response> Function(
  Object error,
  Context<E> c,
);

Aim<E> onError(ErrorHandler<E> handler);
```

```dart
final app = Aim();

app.onError((error, c) async {
  return c.json({'error': error.toString()}, statusCode: 500);
});

app.get('/error', (c) async {
  throw Exception('Something went wrong!');
});
```

If no `onError` handler is registered, the behavior is adapter-specific:
`aim_server` (the `dart:io` adapter) logs the error with its stack trace
and responds with a plain 500. Whether the Workers, Deno, and Cloud
Functions adapters do the same has not been separately verified here —
check each runtime page if that matters for your deployment.

## Authentication Middleware

`app.use()` appends to one middleware list that runs, in registration
order, for **every** request that reaches routing — regardless of whether
the middleware was registered before or after a given route. There is no
way to make a middleware apply "only to routes registered after it".
Registering `requireAuth` after `/login` does **not** exempt `/login`; the
middleware itself must decide which requests to skip:

```dart
class AuthVariables extends Variables {
  String? userId;
}

Future<void> requireAuth(Context<AuthVariables> c, Next next) async {
  const publicPaths = {'/login', '/register'};
  if (publicPaths.contains(c.req.path)) {
    return next();
  }

  final token = c.req.headers['authorization'];

  if (token == null) {
    c.json({'error': 'Missing token'}, statusCode: 401);
    return;
  }

  // Verify token and extract user ID
  final userId = await verifyToken(token);

  if (userId == null) {
    c.json({'error': 'Invalid token'}, statusCode: 401);
    return;
  }

  c.variables.userId = userId;
  return next();
}

void main() async {
  final app = Aim<AuthVariables>(
    variablesFactory: () => AuthVariables(),
  );

  app.use(requireAuth);

  app.post('/login', loginHandler);       // skipped by requireAuth's own check
  app.post('/register', registerHandler); // skipped by requireAuth's own check
  app.get('/profile', profileHandler);
  app.get('/dashboard', dashboardHandler);

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
}
```

`aim_server_jwt`'s built-in middleware has the same constraint and solves
it with `JwtOptions.excludedPaths` instead of an inline path check — see
[JWT Authentication](/server/auth/jwt).

## Conditional Middleware

The same principle applies to any middleware that should only act on part
of the route tree: check the path inside the middleware itself, since
`use()` cannot scope by registration position.

```dart
void main() async {
  final app = Aim();

  // Apply to all routes
  app.use(logger());

  // Public routes
  app.get('/', homeHandler);
  app.get('/about', aboutHandler);

  // Admin routes with auth middleware
  app.use((c, next) async {
    if (c.req.path.startsWith('/admin')) {
      return requireAuth(c, next);
    }
    return next();
  });

  app.get('/admin/dashboard', adminHandler);
  app.get('/admin/users', usersHandler);

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
}
```

## Creating Reusable Middleware

Middleware factories allow configuration:

```dart
// Middleware factory
Middleware<E> timing<E extends Variables>() {
  return (c, next) async {
    final stopwatch = Stopwatch()..start();
    await next();
    stopwatch.stop();
    c.header('X-Response-Time', '${stopwatch.elapsedMilliseconds}ms');
  };
}

// Usage
final app = Aim();
app.use(timing());
```

With parameters:

```dart
Middleware<E> ratelimit<E extends Variables>({
  required int maxRequests,
  required Duration window,
}) {
  final requests = <String, List<DateTime>>{};

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
final app = Aim();
app.use(ratelimit(maxRequests: 100, window: Duration(minutes: 1)));
```

## Built-in Middleware

Aim provides official middleware packages:

```dart
import 'package:aim_server_logger/aim_server_logger.dart';
import 'package:aim_server_cors/aim_server_cors.dart';
import 'package:aim_server_jwt/aim_server_jwt.dart';

final app = Aim<JwtVariables>(
  variablesFactory: () => JwtVariables.create(
    JwtOptions(
      algorithm: HS256(
        secretKey: SecretKey(secret: 'your-secret-key-at-least-32-characters'),
      ),
    ),
  ),
);

// Logger
app.use(logger());

// CORS
app.use(cors(CorsOptions(
  origin: 'https://example.com',
  allowMethods: ['GET', 'POST'],
)));

// JWT Authentication
app.use(jwt());
```

See the [Middleware Packages](/server/middleware/) section for all available middleware.

## Best Practices

1. **Order Matters**: Security/auth middleware should run early
2. **Always Await**: Use `await next()` to ensure proper execution order
3. **Early Return**: Return without calling `next()` to stop the chain
4. **Type Safety**: Use custom `Variables` classes for typed context variables
5. **Error Handling**: Wrap `next()` in try-catch for error handling
6. **Single Responsibility**: Each middleware should do one thing well

## Common Patterns

### Request Timing

```dart
app.use((c, next) async {
  final stopwatch = Stopwatch()..start();
  await next();
  print('Request took ${stopwatch.elapsedMilliseconds}ms');
});
```

### Request/Response Logging

```dart
app.use((c, next) async {
  print('${c.req.method} ${c.req.path}');
  await next();
  print('Response sent');
});
```

### Header Injection

```dart
app.use((c, next) async {
  c.header('X-API-Version', '1.0');
  c.header('X-Request-ID', generateId());
  return next();
});
```

### Body Parsing

```dart
app.use((c, next) async {
  if (c.req.headers['content-type']?.contains('application/json') ?? false) {
    // Parse JSON body and store in context
    final body = await c.req.json();
    // Store for later use
  }
  return next();
});
```

## Next Steps

- Explore the [Context API](/server/concepts/context) for request/response handling
- Browse [Middleware Packages](/server/middleware/) for ready-to-use middleware
- Learn about specific middleware like [CORS](/server/middleware/cors) and [JWT](/server/auth/jwt)
