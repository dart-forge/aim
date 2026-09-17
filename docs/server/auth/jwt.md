---
title: JWT Authentication - Aim Framework
description: Stateless JWT authentication for Dart APIs. HS256 signing, token verification, claims validation, and path exclusion.
head:
  - - meta
    - name: keywords
      content: Dart JWT, JSON Web Token, JWT authentication, stateless auth, token verification, Aim JWT middleware
---

# JWT Authentication

JSON Web Token (JWT) authentication middleware for stateless authentication.

## Installation

```bash
dart pub add aim_server_jwt
```

## Quick Start

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_jwt/aim_server_jwt.dart';

void main() async {
  final app = Aim<JwtVariables>(
    variablesFactory: () => JwtVariables.create(
      JwtOptions(
        algorithm: HS256(
          secretKey: SecretKey(secret: 'your-secret-key-at-least-32-chars'),
        ),
        excludedPaths: ['/login'],
      ),
    ),
  );

  // Apply JWT middleware
  app.use(jwt());

  // Login endpoint (excluded from auth)
  app.post('/login', (c) async {
    // Validate credentials...
    final token = Jwt(options: c.variables.jwtOptions).sign({
      'user_id': 123,
      'username': 'alice',
    });
    return c.json({'token': token});
  });

  // Protected endpoint
  app.get('/profile', (c) async {
    final payload = c.variables.jwtPayload;
    return c.json({
      'user_id': payload['user_id'],
      'username': payload['username'],
    });
  });

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
}
```

## Creating Tokens

### Basic Token

```dart
final jwt = Jwt(options: c.variables.jwtOptions);

final token = jwt.sign({
  'user_id': 123,
  'role': 'admin',
});
```

### With Expiration

```dart
final options = JwtOptions(
  algorithm: HS256(
    secretKey: SecretKey(secret: 'your-secret-key-at-least-32-chars'),
  ),
  expiration: Duration(hours: 24),
);

final token = Jwt(options: options).sign({
  'user_id': 123,
});
```

### With Standard Claims

```dart
final options = JwtOptions(
  algorithm: HS256(
    secretKey: SecretKey(secret: 'your-secret-key-at-least-32-chars'),
  ),
  issuer: 'my-app',
  audience: 'api.example.com',
  expiration: Duration(hours: 24),
);

final token = Jwt(options: options).sign({
  'user_id': 123,
  'permissions': ['read', 'write'],
});

// Generated token includes:
// {
//   "iss": "my-app",
//   "aud": "api.example.com",
//   "exp": <timestamp>,
//   "iat": <timestamp>,
//   "user_id": 123,
//   "permissions": ["read", "write"]
// }
```

## Verifying Tokens

The middleware automatically verifies tokens from the `Authorization` header:

```
Authorization: Bearer <token>
```

Access the verified payload in your handlers:

```dart
app.get('/dashboard', (c) async {
  final payload = c.variables.jwtPayload;
  final userId = payload['user_id'];
  final role = payload['role'];

  return c.json({
    'userId': userId,
    'role': role,
  });
});
```

## Manual Verification

You can also verify tokens manually:

```dart
final jwt = Jwt(options: jwtOptions);

try {
  final claims = jwt.verify(token);
  print('User ID: ${claims['user_id']}');
} on JwtException catch (e) {
  print('Invalid token: ${e.message}');
}
```

## Path Exclusion

Exclude specific paths from authentication:

```dart
final options = JwtOptions(
  algorithm: HS256(
    secretKey: SecretKey(secret: 'your-secret-key-at-least-32-chars'),
  ),
  excludedPaths: ['/login', '/register', '/public', '/health'],
);
```

Public endpoints won't require JWT authentication:

```dart
// No token required
app.post('/login', loginHandler);
app.post('/register', registerHandler);
app.get('/health', healthHandler);

// Token required
app.get('/dashboard', dashboardHandler);
app.get('/profile', profileHandler);
```

## Secret Keys

::: warning Security
The secret key must be at least 32 characters long (RFC 7518 requirement).
:::

**Development:**
```dart
final secret = 'dev-secret-key-at-least-32-chars';
```

**Production:**
```dart
final secret = Platform.environment['JWT_SECRET'] ??
               (throw Exception('JWT_SECRET not set'));

if (secret.length < 32) {
  throw Exception('JWT secret must be at least 32 characters');
}
```

## JWT Options

### JwtOptions Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `algorithm` | `JwtAlgorithm` | required | Signing algorithm (HS256) |
| `issuer` | `String?` | `null` | Token issuer (iss claim) |
| `audience` | `String?` | `null` | Intended audience (aud claim) |
| `expiration` | `Duration?` | `null` | Token lifetime (exp claim) |
| `excludedPaths` | `List<String>` | `[]` | Paths to skip authentication |

### Algorithms

Currently supported:

```dart
// HMAC SHA-256
final algorithm = HS256(
  secretKey: SecretKey(secret: 'your-secret-key'),
);
```

::: info Coming Soon
RS256 (RSA) and ES256 (ECDSA) algorithms will be added in future releases.
:::

## Complete Example

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_jwt/aim_server_jwt.dart';

void main() async {
  // JWT configuration
  final jwtOptions = JwtOptions(
    algorithm: HS256(
      secretKey: SecretKey(
        secret: Platform.environment['JWT_SECRET']!,
      ),
    ),
    issuer: 'my-app',
    audience: 'api.example.com',
    expiration: Duration(hours: 24),
    excludedPaths: ['/login', '/register', '/health'],
  );

  final app = Aim<JwtVariables>(
    variablesFactory: () => JwtVariables.create(jwtOptions),
  );

  app.use(jwt());

  // Health check (no auth)
  app.get('/health', (c) async {
    return c.json({'status': 'ok'});
  });

  // Login (no auth)
  app.post('/login', (c) async {
    final body = await c.req.json();
    final username = body['username'];
    final password = body['password'];

    // Validate credentials...
    if (username != 'admin' || password != 'password') {
      return c.json({'error': 'Invalid credentials'}, statusCode: 401);
    }

    // Create token
    final token = Jwt(options: c.variables.jwtOptions).sign({
      'sub': username,
      'user_id': 123,
      'role': 'admin',
      'permissions': ['read', 'write', 'delete'],
    });

    return c.json({
      'token': token,
      'expires_in': 86400, // 24 hours in seconds
    });
  });

  // Register (no auth)
  app.post('/register', (c) async {
    final body = await c.req.json();
    // Create user...
    return c.json({'message': 'User created'}, statusCode: 201);
  });

  // Protected routes
  app.get('/profile', (c) async {
    final payload = c.variables.jwtPayload;
    return c.json({
      'user_id': payload['user_id'],
      'username': payload['sub'],
      'role': payload['role'],
    });
  });

  app.get('/admin/users', (c) async {
    final payload = c.variables.jwtPayload;

    // Check permissions
    final role = payload['role'];
    if (role != 'admin') {
      return c.json({'error': 'Forbidden'}, statusCode: 403);
    }

    return c.json({
      'users': ['alice', 'bob', 'charlie'],
    });
  });

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
  print('Server running on http://localhost:8080');
}
```

## Testing with curl

### Login

```bash
curl -X POST http://localhost:8080/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"password"}'
```

Response:
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expires_in": 86400
}
```

### Access Protected Route

```bash
curl http://localhost:8080/profile \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

## Error Handling

The middleware returns 401 Unauthorized in these cases:

- Missing `Authorization` header
- Invalid `Authorization` header format (not "Bearer ...")
- Invalid JWT format
- Expired token
- Invalid signature
- Invalid claims (issuer, audience)

All 401 responses include an error message:

```json
{
  "error": "Unauthorized",
  "message": "Invalid or expired token"
}
```

## Best Practices

1. **Use environment variables for secrets**
   ```dart
   final secret = Platform.environment['JWT_SECRET']!;
   ```

2. **Set reasonable expiration times**
   ```dart
   expiration: Duration(hours: 24),  // For web apps
   expiration: Duration(days: 30),   // For mobile apps
   ```

3. **Use standard claims**
   ```dart
   final token = jwt.sign({
     'sub': username,      // Subject (user identifier)
     'user_id': 123,       // Custom claims
     'role': 'admin',
   });
   ```

4. **Validate permissions in handlers**
   ```dart
   app.get('/admin', (c) async {
     final role = c.variables.jwtPayload['role'];
     if (role != 'admin') {
       return c.json({'error': 'Forbidden'}, statusCode: 403);
     }
     // ...
   });
   ```

5. **Refresh tokens for long sessions**
   ```dart
   app.post('/refresh', (c) async {
     // Validate old token...
     final newToken = jwt.sign(payload);
     return c.json({'token': newToken});
   });
   ```

## Security Considerations

- **Always use HTTPS in production** - JWT tokens should be transmitted over secure connections
- **Store tokens securely** - Use HttpOnly cookies or secure storage on mobile
- **Implement token refresh** - Short-lived access tokens with refresh tokens
- **Validate claims** - Check issuer, audience, and custom claims
- **Rotate secrets** - Change JWT secrets periodically

## Next Steps

- Learn about [Basic Auth](/server/auth/basic-auth) for simpler authentication
- Explore [Cookie middleware](/server/middleware/cookie) for session management
- Read about [Middleware patterns](/server/concepts/middleware)
