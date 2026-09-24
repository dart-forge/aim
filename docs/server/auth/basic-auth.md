---
title: Basic Authentication - Aim Framework
description: HTTP Basic Authentication for Dart. RFC 7617 compliant, realm configuration, and custom verification functions.
head:
  - - meta
    - name: keywords
      content: Dart Basic Auth, HTTP authentication, RFC 7617, username password auth, Aim basic auth middleware
---

# Basic Authentication

HTTP Basic Authentication middleware (RFC 7617 compliant).

## Installation

```bash
dart pub add aim_server_basic_auth
```

## Quick Start

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_basic_auth/aim_server_basic_auth.dart';

void main() async {
  final app = Aim<BasicAuthVariables>(
    variablesFactory: () => BasicAuthVariables(
      options: BasicAuthOptions(
        realm: 'Admin Area',
        verify: (username, password) async {
          return username == 'admin' && password == 'secret123';
        },
      ),
    ),
  );

  app.use(basicAuth());

  app.get('/admin', (c) async {
    final username = c.variables.username;
    return c.json({'message': 'Welcome, $username!'});
  });

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
}
```

## How It Works

1. Client requests a protected resource
2. Server returns `401 Unauthorized` with `WWW-Authenticate` header
3. Browser shows authentication dialog
4. Client sends credentials as `Authorization: Basic base64(username:password)`
5. Server verifies credentials and grants or denies access

```
Client                          Server
  |                               |
  |------ GET /admin ------------>|
  |<----- 401 Unauthorized -------| WWW-Authenticate: Basic realm="Admin Area"
  |                               |
  | [Browser shows dialog]        |
  |                               |
  |------ GET /admin ------------>| Authorization: Basic YWRtaW46c2VjcmV0
  |<----- 200 OK -----------------| {\"message\": \"Welcome, admin!\"}
```

## Configuration

### Basic Setup

```dart
final options = BasicAuthOptions(
  realm: 'Admin Dashboard',
  verify: (username, password) async {
    return username == 'admin' && password == 'secret';
  },
);
```

### Database Verification

```dart
final options = BasicAuthOptions(
  realm: 'My Application',
  verify: (username, password) async {
    // Fetch user from database
    final user = await database.findUserByUsername(username);
    if (user == null) return false;

    // Verify password hash
    return BCrypt.checkpw(password, user.passwordHash);
  },
);
```

### With Path Exclusion

```dart
final options = BasicAuthOptions(
  realm: 'Protected Area',
  verify: (username, password) async {
    return username == 'admin' && password == 'secret';
  },
  excludedPaths: ['/login', '/register', '/public', '/health'],
);
```

## Path Exclusion

Skip authentication for specific routes:

```dart
final app = Aim<BasicAuthVariables>(
  variablesFactory: () => BasicAuthVariables(
    options: BasicAuthOptions(
      realm: 'Admin Area',
      verify: verifyCredentials,
      excludedPaths: ['/login', '/health'],
    ),
  ),
);

app.use(basicAuth());

// Public endpoint (no authentication)
app.get('/login', (c) async {
  return c.html('<form>...</form>');
});

// Protected endpoint (authentication required)
app.get('/dashboard', (c) async {
  final username = c.variables.username;
  return c.json({'user': username});
});
```

## Realm

The realm identifier appears in the browser's authentication dialog:

```dart
final options = BasicAuthOptions(
  realm: 'Staff Only Area',  // Shown to users
  verify: verifyCredentials,
);
```

This helps users understand what they're logging into and allows browsers to cache credentials per realm.

## Accessing Username

After successful authentication, the username is available in the context:

```dart
app.get('/profile', (c) async {
  final username = c.variables.username;

  return c.json({
    'username': username,
    'message': 'Your profile data',
  });
});
```

## Complete Example

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_basic_auth/aim_server_basic_auth.dart';

void main() async {
  // Configuration
  final options = BasicAuthOptions(
    realm: 'Admin Dashboard',
    verify: (username, password) async {
      // In production, verify against database with hashed passwords
      final validUsers = {
        'admin': 'admin_password_hash',
        'user': 'user_password_hash',
      };

      return validUsers[username] == password;
    },
    excludedPaths: ['/login', '/health', '/public'],
  );

  final app = Aim<BasicAuthVariables>(
    variablesFactory: () => BasicAuthVariables(options: options),
  );

  app.use(basicAuth());

  // Health check (excluded)
  app.get('/health', (c) async => c.json({'status': 'ok'}));

  // Login page (excluded)
  app.get('/login', (c) async {
    return c.html('''
      <h1>Login</h1>
      <p>Use HTTP Basic Authentication to access protected resources.</p>
    ''');
  });

  // Protected routes
  app.get('/admin/dashboard', (c) async {
    final username = c.variables.username;
    return c.json({
      'page': 'dashboard',
      'user': username,
      'timestamp': DateTime.now().toIso8601String(),
    });
  });

  app.get('/admin/users', (c) async {
    final username = c.variables.username;
    return c.json({
      'page': 'users',
      'admin': username,
      'users': ['alice', 'bob', 'charlie'],
    });
  });

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
  print('Server running on http://localhost:8080');
}
```

## Security Best Practices

### 1. Always Use HTTPS in Production

Basic Auth sends credentials in Base64 encoding (not encryption). **Always use HTTPS** to prevent interception.

```dart
// Production
final server = await app.serve(
  host: InternetAddress.anyIPv4,
  port: 443,
  securityContext: SecurityContext()
    ..useCertificateChain('server_chain.pem')
    ..usePrivateKey('server_key.pem'),
);
```

### 2. Use Strong Password Hashing

Never store or compare plaintext passwords:

```dart
import 'package:bcrypt/bcrypt.dart';

verify: (username, password) async {
  final user = await db.findUser(username);
  if (user == null) return false;

  // Verify hashed password
  return BCrypt.checkpw(password, user.passwordHash);
}
```

### 3. Implement Rate Limiting

Protect against brute force attacks:

```dart
final loginAttempts = <String, int>{};

verify: (username, password) async {
  // Check rate limit
  final attempts = loginAttempts[username] ?? 0;
  if (attempts >= 5) {
    return false; // Locked out
  }

  final isValid = await authService.verify(username, password);

  if (!isValid) {
    loginAttempts[username] = attempts + 1;
  } else {
    loginAttempts.remove(username);
  }

  return isValid;
}
```

### 4. Never Log Passwords

```dart
// ❌ Bad
print('Login attempt: $username:$password');

// ✅ Good
print('Login attempt for user: $username');
```

### 5. Use Environment Variables

```dart
final secret = Platform.environment['ADMIN_PASSWORD'] ??
               (throw Exception('ADMIN_PASSWORD not set'));
```

## Error Handling

The middleware returns `401 Unauthorized` in these cases:

- Missing `Authorization` header
- Invalid `Authorization` header format (not "Basic ...")
- Invalid Base64 encoding
- Missing colon separator in credentials
- Verification function returns `false`

All 401 responses include the `WWW-Authenticate` header:

```
HTTP/1.1 401 Unauthorized
WWW-Authenticate: Basic realm="Admin Area"
Content-Type: application/json

{"error": "Unauthorized"}
```

## Special Cases

### Passwords with Colons

The middleware correctly handles passwords containing colons:

```dart
// Password: "my:password:with:colons"
// Credentials: username:my:password:with:colons
// ✅ Correctly parsed as:
//    username = "username"
//    password = "my:password:with:colons"
```

### Empty Passwords

Empty passwords are supported (though not recommended):

```dart
verify: (username, password) async {
  return username == 'user' && password == '';
}
```

### Unicode Characters

Full Unicode support in usernames and passwords:

```dart
verify: (username, password) async {
  return username == 'ユーザー' && password == 'パスワード';
}
```

## Comparison with JWT

| Feature | Basic Auth | JWT |
|---------|-----------|-----|
| **Stateless** | ✅ Yes | ✅ Yes |
| **Sends credentials** | Every request | Only during login |
| **Token expiration** | ❌ No | ✅ Yes |
| **Complexity** | Very simple | More complex |
| **Best for** | Internal tools, admin panels | Public APIs, mobile apps |
| **HTTPS required** | ✅ Critical | ✅ Recommended |
| **Browser support** | ✅ Native | ⚠️ Requires JavaScript |

## When to Use Basic Auth

Use Basic Auth for:
- Internal admin dashboards
- Development/staging environments
- Simple authentication needs
- Legacy system compatibility
- Tools and internal APIs

Use JWT for:
- Public-facing APIs
- Mobile applications
- Token expiration requirements
- Stateless microservices

## BasicAuthOptions Reference

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `realm` | `String` | `'Restricted Area'` | Realm identifier shown to users |
| `verify` | `Function` | required | Async function to verify credentials |
| `excludedPaths` | `List<String>` | `[]` | Paths to skip authentication |

## Next Steps

- Learn about [JWT Authentication](/server/auth/jwt) for token-based auth
- Explore [Cookie middleware](/server/middleware/cookie) for session management
- Read about [Security best practices](/server/guides/best-practices#security)
