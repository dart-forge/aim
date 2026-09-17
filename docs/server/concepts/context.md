---
title: Context API - Aim Framework
description: Deep dive into Aim's Context API. Handle requests, responses, headers, and type-safe context variables in Dart server applications.
head:
  - - meta
    - name: keywords
      content: Dart Context API, request handling, response methods, context variables, type-safe, Aim context
---

# Context

The `Context` object is the heart of Aim. It provides access to the request, response, and per-request context variables for each HTTP request.

## Overview

Every route handler and middleware receives a `Context` object:

```dart
app.get('/hello', (c) async {
  // c is the Context object
  return c.text('Hello!');
});
```

## Request (`c.req`)

Access request information through `c.req`:

### Method and Path

```dart
app.all('/*', (c) async {
  final method = c.req.method;  // GET, POST, etc.
  final path = c.req.path;      // /users/123

  return c.json({
    'method': method,
    'path': path,
  });
});
```

### Headers

```dart
app.get('/headers', (c) async {
  final headers = c.req.headers;  // Map<String, String>
  final userAgent = c.req.headers['user-agent'];
  final auth = c.req.headers['authorization'];

  return c.json({
    'userAgent': userAgent,
    'auth': auth,
  });
});
```

### Query Parameters

```dart
app.get('/search', (c) async {
  final queries = c.req.queries;  // Map<String, List<String>>
  final q = c.req.queries['q']?.first;
  final page = c.req.queries['page']?.first ?? '1';

  return c.json({
    'query': q,
    'page': int.parse(page),
  });
});
```

Example: `GET /search?q=dart&page=2`

### Request Body

#### JSON Body

```dart
app.post('/users', (c) async {
  final body = await c.req.json();  // Map<String, dynamic>
  final name = body['name'];
  final email = body['email'];

  return c.json({
    'created': {
      'name': name,
      'email': email,
    },
  }, statusCode: 201);
});
```

#### Raw Body

```dart
app.post('/webhook', (c) async {
  final raw = await c.req.raw();  // List<int>
  final text = utf8.decode(raw);

  return c.text('Received ${raw.length} bytes');
});
```

#### Form Data

Use the `aim_server_form` middleware:

```dart
import 'package:aim_server_form/aim_server_form.dart';

final app = Aim<FormVariables>(
  variablesFactory: () => FormVariables(),
);

app.use(form());

app.post('/login', (c) async {
  final username = c.variables.formData['username'];
  final password = c.variables.formData['password'];

  return c.json({'username': username});
});
```

#### Multipart/File Upload

Use the `aim_server_multipart` middleware:

```dart
import 'package:aim_server_multipart/aim_server_multipart.dart';

final app = Aim<MultipartVariables>(
  variablesFactory: () => MultipartVariables(),
);

app.use(multipart());

app.post('/upload', (c) async {
  final files = c.variables.files;
  final file = files['avatar'];

  if (file != null) {
    await File('uploads/${file.filename}').writeAsBytes(file.bytes);
  }

  return c.json({'uploaded': file?.filename});
});
```

## Path Parameters

Extract parameters from the URL path using `c.param()`:

```dart
// Single parameter
app.get('/users/:id', (c) async {
  final id = c.param('id');
  return c.json({'userId': id});
});

// Multiple parameters
app.get('/posts/:postId/comments/:commentId', (c) async {
  final postId = c.param('postId');
  final commentId = c.param('commentId');

  return c.json({
    'postId': postId,
    'commentId': commentId,
  });
});
```

## Response Methods

### JSON Response

```dart
app.get('/api/users', (c) async {
  return c.json({
    'users': [
      {'id': 1, 'name': 'Alice'},
      {'id': 2, 'name': 'Bob'},
    ],
  });
});

// With status code
app.post('/users', (c) async {
  return c.json({'created': true}, statusCode: 201);
});
```

### Text Response

```dart
app.get('/hello', (c) async {
  return c.text('Hello, World!');
});

// With status code
app.get('/not-found', (c) async {
  return c.text('Not Found', statusCode: 404);
});
```

### HTML Response

```dart
app.get('/page', (c) async {
  return c.html('''
    <!DOCTYPE html>
    <html>
      <head><title>My Page</title></head>
      <body><h1>Hello!</h1></body>
    </html>
  ''');
});
```

### File Response

```dart
import 'dart:io';

app.get('/download', (c) async {
  final file = File('assets/document.pdf');
  final bytes = await file.readAsBytes();

  c.header('Content-Type', 'application/pdf');
  c.header('Content-Disposition', 'attachment; filename="document.pdf"');

  return c.bytes(bytes);
});
```

### Redirect

```dart
app.get('/old-path', (c) async {
  return c.redirect('/new-path');
});

// With status code
app.get('/temp-redirect', (c) async {
  return c.redirect('/new-path', statusCode: 302);
});
```

### Stream Response

```dart
app.get('/stream', (c) async {
  final stream = Stream.periodic(
    Duration(seconds: 1),
    (count) => 'Event $count\n',
  ).take(10);

  return c.stream(stream);
});
```

For Server-Sent Events (SSE), use the `aim_server_sse` package:

```dart
import 'package:aim_server_sse/aim_server_sse.dart';

final app = Aim<SseVariables>(
  variablesFactory: () => SseVariables(),
);

app.use(sse());

app.get('/events', (c) async {
  return c.sse((sink) async {
    for (var i = 0; i < 10; i++) {
      await Future.delayed(Duration(seconds: 1));
      sink.sendEvent(data: 'Event $i');
    }
  });
});
```

## Response Headers

Set headers before sending the response:

```dart
app.get('/api', (c) async {
  c.header('X-API-Version', '1.0');
  c.header('X-Request-ID', generateId());
  c.header('Cache-Control', 'no-cache');

  return c.json({'data': 'value'});
});
```

## Variables

Use custom `Variables` classes for type-safe context variables:

```dart
class AppVariables extends Variables {
  String? userId;
  String? requestId;
  DateTime? requestTime;
}

final app = Aim<AppVariables>(
  variablesFactory: () => AppVariables(),
);

// Set in middleware
app.use((c, next) async {
  c.variables.requestId = generateId();
  c.variables.requestTime = DateTime.now();
  return next();
});

// Use in handlers
app.get('/info', (c) async {
  return c.json({
    'requestId': c.variables.requestId,
    'time': c.variables.requestTime?.toIso8601String(),
  });
});
```

::: tip Variables vs. runtime env
`Variables` are per-request values your middleware and handlers share. Runtime bindings such as Cloudflare Workers' `env` are a different concept and are exposed by the runtime adapter (for example `c.env` in `aim_edge`).
:::

### Middleware-Specific Variables

Many middleware packages extend the base `Variables`:

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
  final payload = c.variables.jwtPayload;  // From JWT middleware
  return c.json({'userId': payload['sub']});
});
```

## Context Lifecycle

1. **Request arrives** → Aim creates a new `Context`
2. **Middleware chain** → Each middleware can modify the context
3. **Route handler** → Handler uses context to generate response
4. **Response sent** → Context is discarded

```dart
app.use((c, next) async {
  print('1. Middleware - before');
  c.variables.startTime = DateTime.now();
  await next();
  print('4. Middleware - after');
});

app.get('/', (c) async {
  print('2. Handler - start');
  final response = c.json({'message': 'Hello'});
  print('3. Handler - end');
  return response;
});

// Output:
// 1. Middleware - before
// 2. Handler - start
// 3. Handler - end
// 4. Middleware - after
```

## Best Practices

### Type-Safe Variables

```dart
// ✅ Good - Type-safe
class MyVariables extends Variables {
  String? userId;
}

final app = Aim<MyVariables>(
  variablesFactory: () => MyVariables(),
);

// ❌ Bad - No type safety
final app = Aim();
// No compile-time checking
```

### Early Returns

```dart
// ✅ Good - Clear and concise
app.get('/users/:id', (c) async {
  final id = c.param('id');

  if (id == null) {
    return c.json({'error': 'Missing ID'}, statusCode: 400);
  }

  final user = await findUser(id);

  if (user == null) {
    return c.json({'error': 'Not found'}, statusCode: 404);
  }

  return c.json(user);
});
```

### Header Setting

```dart
// ✅ Good - Set headers before response
app.get('/api', (c) async {
  c.header('X-Version', '1.0');
  return c.json({'data': 'value'});
});

// ❌ Bad - Headers after response (won't work)
app.get('/api', (c) async {
  final response = c.json({'data': 'value'});
  c.header('X-Version', '1.0');  // Too late!
  return response;
});
```

## Complete Example

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';

class AppVariables extends Variables {
  String? userId;
  String? requestId;
  DateTime? startTime;
}

void main() async {
  final app = Aim<AppVariables>(
    variablesFactory: () => AppVariables(),
  );

  // Middleware to track request
  app.use((c, next) async {
    c.variables.requestId = generateId();
    c.variables.startTime = DateTime.now();

    c.header('X-Request-ID', c.variables.requestId!);

    await next();

    final elapsed = DateTime.now().difference(c.variables.startTime!);
    print('Request took ${elapsed.inMilliseconds}ms');
  });

  // Routes
  app.get('/', (c) async {
    return c.json({
      'message': 'Welcome',
      'requestId': c.variables.requestId,
    });
  });

  app.get('/users/:id', (c) async {
    final id = c.param('id');

    return c.json({
      'userId': id,
      'requestId': c.variables.requestId,
    });
  });

  app.post('/users', (c) async {
    final body = await c.req.json();

    return c.json({
      'created': body,
      'requestId': c.variables.requestId,
    }, statusCode: 201);
  });

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
  print('Server running on http://localhost:8080');
}

String generateId() {
  return DateTime.now().millisecondsSinceEpoch.toString();
}
```

## Next Steps

- Learn about [Middleware](/server/concepts/middleware) to process requests
- Explore [Middleware Packages](/server/middleware/) for common functionality
- Check out specific middleware like [JWT](/server/auth/jwt) or [CORS](/server/middleware/cors)
