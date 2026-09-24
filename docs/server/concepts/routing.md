---
title: Routing - Aim Framework
description: Learn about Aim's flexible routing system. Path parameters, wildcards, route groups, and RESTful API patterns for Dart server applications.
head:
  - - meta
    - name: keywords
      content: Dart routing, path parameters, wildcards, route groups, REST API, Dart server, Aim routing
---

# Routing

Aim provides a simple and flexible routing system that supports path parameters, wildcards, and HTTP method-based routing.

## Basic Routing

Define routes using HTTP method functions:

```dart
final app = Aim();

app.get('/users', (c) async {
  return c.json({'users': []});
});

app.post('/users', (c) async {
  final body = await c.req.json();
  return c.json({'created': body}, statusCode: 201);
});

app.put('/users/:id', (c) async {
  final id = c.param('id');
  final body = await c.req.json();
  return c.json({'updated': id, 'data': body});
});

app.delete('/users/:id', (c) async {
  final id = c.param('id');
  return c.json({'deleted': id});
});
```

## HTTP Methods

Aim supports all standard HTTP methods:

```dart
app.get('/resource', handler);      // GET
app.post('/resource', handler);     // POST
app.put('/resource', handler);      // PUT
app.delete('/resource', handler);   // DELETE
app.patch('/resource', handler);    // PATCH
app.head('/resource', handler);     // HEAD
app.options('/resource', handler);  // OPTIONS
```

## Route Groups

Group related routes under a common base path using `app.route()`:

```dart
final app = Aim();

// Create API routes group
final api = Aim();
api.get('/users', getUsersHandler);
api.post('/users', createUserHandler);
api.get('/posts', getPostsHandler);

// Mount under /api
app.route('/api', api);

// Routes are now:
// GET  /api/users
// POST /api/users
// GET  /api/posts
```

### Organizing Routes by Module

```dart
// lib/routes/users.dart
Aim createUserRoutes() {
  final users = Aim();

  users.get('/', getAllUsers);
  users.get('/:id', getUserById);
  users.post('/', createUser);
  users.put('/:id', updateUser);
  users.delete('/:id', deleteUser);

  return users;
}

// lib/routes/posts.dart
Aim createPostRoutes() {
  final posts = Aim();

  posts.get('/', getAllPosts);
  posts.get('/:id', getPostById);
  posts.post('/', createPost);

  return posts;
}

// bin/server.dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:my_app/routes/users.dart';
import 'package:my_app/routes/posts.dart';

void main() async {
  final app = Aim();

  // Mount route groups
  app.route('/users', createUserRoutes());
  app.route('/posts', createPostRoutes());

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
}
```

### Nested Route Groups

```dart
final app = Aim();

// Admin routes
final admin = Aim();
admin.get('/dashboard', adminDashboard);

final adminUsers = Aim();
adminUsers.get('/', listAdminUsers);
adminUsers.post('/', createAdminUser);

admin.route('/users', adminUsers);
app.route('/admin', admin);

// Routes:
// GET  /admin/dashboard
// GET  /admin/users
// POST /admin/users
```

### Version-based Routing

```dart
final app = Aim();

// API v1
final v1 = Aim();
v1.get('/users', getUsersV1);
v1.get('/posts', getPostsV1);

// API v2
final v2 = Aim();
v2.get('/users', getUsersV2);
v2.get('/posts', getPostsV2);

app.route('/v1', v1);
app.route('/v2', v2);

// Routes:
// GET /v1/users
// GET /v1/posts
// GET /v2/users
// GET /v2/posts
```

## Path Parameters

Extract dynamic segments from the URL path using the `:param` syntax:

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

// Parameters in the middle
app.get('/users/:userId/posts/:postId/edit', (c) async {
  final userId = c.param('userId');
  final postId = c.param('postId');
  return c.text('Edit post $postId for user $userId');
});
```

## Wildcard Routes

Use `*` to match any path segment:

```dart
// Match all paths under /api
app.get('/api/*', (c) async {
  final path = c.req.path;
  return c.json({'path': path});
});

// 404 handler (must be defined last)
app.notFound((c) async {
  return c.json({'error': 'Not Found'}, statusCode: 404);
});
```

## All Methods

Use `app.all()` to register a single handler for every HTTP method on a path:

```dart
// Handle all methods for a specific path
app.all('/webhook', (c) async {
  final method = c.req.method;
  return c.json({'received': method});
});

// Global 404 handler
app.notFound((c) async {
  return c.json({
    'error': 'Not Found',
    'path': c.req.path,
  }, statusCode: 404);
});
```

Like every other route, `app.all()` follows the declaration-order rule: the
first matching route wins. An `all()` declared before a more specific `get()`
on the same path handles GET too, while a `get()` declared first still wins
for GET and leaves the rest to `all()`.

## Query Parameters

Access query parameters through the request object:

```dart
app.get('/search', (c) async {
  final query = c.req.queryParameters; // Map<String, String>
  final q = query['q'];
  final page = query['page'] ?? '1';

  return c.json({
    'query': q,
    'page': page,
  });
});
```

Example request:
```
GET /search?q=dart&page=2
```

## Route Patterns

### Static Routes

Exact path matching:

```dart
app.get('/about', handler);
app.get('/contact', handler);
app.get('/api/v1/users', handler);
```

### Dynamic Routes

With path parameters:

```dart
app.get('/users/:id', handler);
app.get('/posts/:slug', handler);
app.get('/:lang/posts/:id', handler);
```

### Mixed Routes

Combining static and dynamic segments:

```dart
app.get('/api/users/:id', handler);
app.get('/admin/posts/:id/edit', handler);
app.get('/v1/:resource/:id', handler);
```

## Route Priority

Routes are matched in the order they are defined. More specific routes should be defined before more general ones:

```dart
// ✅ Correct order
app.get('/users/me', (c) async {
  return c.json({'message': 'Current user'});
});

app.get('/users/:id', (c) async {
  final id = c.param('id');
  return c.json({'userId': id});
});

// ❌ Wrong order - '/users/me' would match ':id'
app.get('/users/:id', handler);
app.get('/users/me', handler);  // This will never match!
```

## RESTful API Example

Here's a complete RESTful API example:

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';

void main() async {
  final app = Aim();

  // List all users
  app.get('/users', (c) async {
    return c.json({
      'users': [
        {'id': '1', 'name': 'Alice'},
        {'id': '2', 'name': 'Bob'},
      ],
    });
  });

  // Get single user
  app.get('/users/:id', (c) async {
    final id = c.param('id');
    return c.json({
      'id': id,
      'name': 'Alice',
      'email': 'alice@example.com',
    });
  });

  // Create user
  app.post('/users', (c) async {
    final body = await c.req.json();
    return c.json({
      'id': '3',
      'name': body['name'],
      'email': body['email'],
    }, statusCode: 201);
  });

  // Update user
  app.put('/users/:id', (c) async {
    final id = c.param('id');
    final body = await c.req.json();
    return c.json({
      'id': id,
      'name': body['name'],
      'email': body['email'],
    });
  });

  // Partial update
  app.patch('/users/:id', (c) async {
    final id = c.param('id');
    final body = await c.req.json();
    return c.json({
      'id': id,
      'updated': body,
    });
  });

  // Delete user
  app.delete('/users/:id', (c) async {
    final id = c.param('id');
    return c.json({'deleted': id}, statusCode: 200);
  });

  // Nested resources
  app.get('/users/:userId/posts', (c) async {
    final userId = c.param('userId');
    return c.json({
      'userId': userId,
      'posts': [],
    });
  });

  app.post('/users/:userId/posts', (c) async {
    final userId = c.param('userId');
    final body = await c.req.json();
    return c.json({
      'userId': userId,
      'post': body,
    }, statusCode: 201);
  });

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
  print('API server running on http://localhost:8080');
}
```

## Error Handling

Handle routes that don't exist:

```dart
final app = Aim();

// Your routes
app.get('/', handler);
app.get('/users', handler);

// 404 handler (must be last)
app.notFound((c) async {
  return c.json({
    'error': 'Not Found',
    'path': c.req.path,
    'method': c.req.method,
  }, statusCode: 404);
});
```

## Best Practices

1. **Order Matters**: Define specific routes before generic ones
2. **Use RESTful Conventions**: Follow standard HTTP method semantics
3. **Validate Parameters**: Check path parameters and query strings
4. **404 Handler**: Always add a catch-all 404 handler at the end
5. **Consistent Naming**: Use plural nouns for resources (`/users`, not `/user`)

## Next Steps

- Learn about [Middleware](/server/concepts/middleware) to add cross-cutting concerns
- Explore the [Context API](/server/concepts/context) for request/response handling
- Check out [Middleware Packages](/server/middleware/) for authentication, CORS, and more
