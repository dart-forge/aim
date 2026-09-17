---
title: Quick Start - Aim Framework
description: Build your first Dart server application with Aim. Learn routing, middleware, and context variables in minutes.
---

# Quick Start

Build your first Aim application in minutes.

## Your First Application

Create a file `bin/server.dart`:

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';

void main() async {
  // Create an Aim application
  final app = Aim();

  // Define a route
  app.get('/', (c) async {
    return c.text('Hello, Aim!');
  });

  // Start the server
  await app.serve(
    host: InternetAddress.anyIPv4,
    port: 8080,
  );

  print('Server running on http://localhost:8080');
}
```

Run your application:

```bash
dart run bin/server.dart
```

Visit `http://localhost:8080` - you should see "Hello, Aim!"

## Adding Routes

Let's add more routes to handle different HTTP methods and path parameters:

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';

void main() async {
  final app = Aim();

  // GET request
  app.get('/', (c) async {
    return c.text('Hello, Aim!');
  });

  // Path parameters
  app.get('/users/:id', (c) async {
    final id = c.param('id');
    return c.json({'userId': id});
  });

  // POST request
  app.post('/users', (c) async {
    final body = await c.req.json();
    return c.json({'created': body}, statusCode: 201);
  });

  // Multiple path parameters
  app.get('/posts/:postId/comments/:commentId', (c) async {
    final postId = c.param('postId');
    final commentId = c.param('commentId');
    return c.json({
      'postId': postId,
      'commentId': commentId,
    });
  });

  await app.serve(
    host: InternetAddress.anyIPv4,
    port: 8080,
  );

  print('Server running on http://localhost:8080');
}
```

## Using Middleware

Middleware functions run before your route handlers. They're perfect for logging, authentication, CORS, and more.

First, add the logger middleware package:

```bash
dart pub add aim_server_logger
```

Then use it in your app:

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_logger/aim_server_logger.dart';

void main() async {
  final app = Aim();

  // Add logger middleware
  app.use(logger());

  app.get('/', (c) async {
    return c.text('Hello, Aim!');
  });

  await app.serve(
    host: InternetAddress.anyIPv4,
    port: 8080,
  );

  print('Server running on http://localhost:8080');
}
```

Now all requests will be logged to the console:

```
<-- GET /
--> GET / 200 2ms
```

## Variables

Use custom `Variables` classes for type-safe variable storage:

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';

// Define your context variables
class MyVariables extends Variables {
  String? requestId;
  String? userId;
}

void main() async {
  final app = Aim<MyVariables>(
    variablesFactory: () => MyVariables(),
  );

  // Middleware to set request ID
  app.use((c, next) async {
    c.variables.requestId = DateTime.now().millisecondsSinceEpoch.toString();
    return next();
  });

  app.get('/user', (c) async {
    // Access typed variables
    final requestId = c.variables.requestId;
    return c.json({
      'requestId': requestId,
      'message': 'User info',
    });
  });

  await app.serve(
    host: InternetAddress.anyIPv4,
    port: 8080,
  );

  print('Server running on http://localhost:8080');
}
```

## Development Server

Use the Aim CLI for hot reload during development:

```bash
aim dev
```

The dev server will:
- Watch for file changes in `lib/` and `bin/`
- Automatically restart your server
- Preserve your terminal output history

Configure the dev server in `pubspec.yaml`:

```yaml
aim:
  entry: bin/server.dart
  env:
    PORT: "8080"
    DATABASE_URL: ${DATABASE_URL}  # Expand from system env
```

## Complete Example

Here's a more complete example combining what we've learned:

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_logger/aim_server_logger.dart';
import 'package:aim_server_cors/aim_server_cors.dart';

class AppVariables extends Variables {
  String? requestId;
}

void main() async {
  final app = Aim<AppVariables>(
    variablesFactory: () => AppVariables(),
  );

  // Middleware
  app.use(logger());
  app.use(cors());

  // Request ID middleware
  app.use((c, next) async {
    c.variables.requestId = DateTime.now().millisecondsSinceEpoch.toString();
    return next();
  });

  // Routes
  app.get('/', (c) async {
    return c.json({
      'message': 'Welcome to Aim API',
      'requestId': c.variables.requestId,
    });
  });

  app.get('/users/:id', (c) async {
    final id = c.param('id');
    return c.json({
      'id': id,
      'name': 'John Doe',
      'requestId': c.variables.requestId,
    });
  });

  app.post('/users', (c) async {
    final body = await c.req.json();
    return c.json({
      'message': 'User created',
      'data': body,
      'requestId': c.variables.requestId,
    }, statusCode: 201);
  });

  // 404 handler
  app.notFound((c) async {
    return c.json({
      'error': 'Not Found',
      'requestId': c.variables.requestId,
    }, statusCode: 404);
  });

  await app.serve(
    host: InternetAddress.anyIPv4,
    port: 8080,
  );

  print('🚀 Server running on http://localhost:8080');
}
```

## Next Steps

Now that you have a basic application running, explore:

- [Routing](/server/concepts/routing) - Learn about advanced routing patterns
- [Middleware](/server/concepts/middleware) - Understand the middleware system
- [Context](/server/concepts/context) - Deep dive into the Context API
- [Middleware Packages](/server/middleware/) - Add CORS, auth, and more
- [Cloudflare Workers](/server/edge) - Deploy the same app to the edge with `aim create --target edge`

Happy coding with Aim!
