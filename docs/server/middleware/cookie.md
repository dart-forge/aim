---
title: Cookie Middleware - Aim Framework
description: Secure cookie management for Dart servers. HttpOnly, Secure, SameSite, and expiration settings for safe session handling.
head:
  - - meta
    - name: keywords
      content: Dart cookie, HttpOnly, Secure cookie, SameSite, session management, Aim cookie middleware
---

# Cookie

Secure cookie management middleware.

## Installation

```bash
dart pub add aim_server_cookie
```

## Quick Start

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_cookie/aim_server_cookie.dart';

void main() async {
  final app = Aim<CookieVariables>(
    variablesFactory: () => CookieVariables(),
  );

  app.use(cookie());

  app.get('/set', (c) async {
    c.variables.setCookie('session_id', 'abc123');
    return c.text('Cookie set');
  });

  app.get('/get', (c) async {
    final sessionId = c.variables.getCookie('session_id');
    return c.text('Session: $sessionId');
  });

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
}
```

## Setting Cookies

### Basic Cookie

```dart
c.variables.setCookie('user_id', '123');
```

### With Options

```dart
c.variables.setCookie(
  'session_id',
  'abc123',
  options: CookieOptions(
    httpOnly: true,
    secure: true,
    maxAge: Duration(days: 7),
    sameSite: SameSite.lax,
  ),
);
```

### Secure Cookie

```dart
c.variables.setCookie(
  'auth_token',
  'secret-token',
  options: CookieOptions(
    httpOnly: true,   // Prevent JavaScript access
    secure: true,     // HTTPS only
    sameSite: SameSite.strict,
  ),
);
```

## Getting Cookies

```dart
app.get('/profile', (c) async {
  final userId = c.variables.getCookie('user_id');

  if (userId == null) {
    return c.json({'error': 'Not logged in'}, statusCode: 401);
  }

  return c.json({'userId': userId});
});
```

## Deleting Cookies

```dart
app.get('/logout', (c) async {
  c.variables.deleteCookie('session_id');
  c.variables.deleteCookie('user_id');
  return c.text('Logged out');
});
```

## Cookie Options

### `httpOnly`

Prevents JavaScript access to the cookie:

```dart
CookieOptions(
  httpOnly: true, // Cannot be accessed via document.cookie
)
```

**Use for**: Session tokens, auth tokens

### `secure`

Requires HTTPS:

```dart
CookieOptions(
  secure: true, // Only sent over HTTPS
)
```

**Use for**: Production environments

### `maxAge`

Cookie expiration time:

```dart
CookieOptions(
  maxAge: Duration(days: 7), // Expires in 7 days
)
```

### `expires`

Specific expiration date:

```dart
CookieOptions(
  expires: DateTime.now().add(Duration(days: 30)),
)
```

### `domain`

Cookie domain:

```dart
CookieOptions(
  domain: '.example.com', // Available to all subdomains
)
```

### `path`

Cookie path:

```dart
CookieOptions(
  path: '/admin', // Only available under /admin
)
```

### `sameSite`

CSRF protection:

```dart
// Strict - Never sent with cross-site requests
CookieOptions(sameSite: SameSite.strict)

// Lax - Sent with top-level navigation
CookieOptions(sameSite: SameSite.lax)

// None - Sent with all requests (requires secure: true)
CookieOptions(sameSite: SameSite.none, secure: true)
```

## Complete Example

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_cookie/aim_server_cookie.dart';

void main() async {
  final app = Aim<CookieVariables>(
    variablesFactory: () => CookieVariables(),
  );

  app.use(cookie());

  // Login
  app.post('/login', (c) async {
    final body = await c.req.json();
    final username = body['username'];
    final password = body['password'];

    // Validate credentials...
    if (username == 'admin' && password == 'password') {
      // Set secure session cookie
      c.variables.setCookie(
        'session_id',
        generateSessionId(),
        options: CookieOptions(
          httpOnly: true,
          secure: true,
          maxAge: Duration(days: 7),
          sameSite: SameSite.lax,
        ),
      );

      // Set user preference cookie
      c.variables.setCookie(
        'theme',
        'dark',
        options: CookieOptions(
          maxAge: Duration(days: 365),
        ),
      );

      return c.json({'message': 'Logged in'});
    }

    return c.json({'error': 'Invalid credentials'}, statusCode: 401);
  });

  // Profile (requires session)
  app.get('/profile', (c) async {
    final sessionId = c.variables.getCookie('session_id');

    if (sessionId == null) {
      return c.json({'error': 'Not authenticated'}, statusCode: 401);
    }

    // Validate session...
    final theme = c.variables.getCookie('theme') ?? 'light';

    return c.json({
      'username': 'admin',
      'theme': theme,
    });
  });

  // Logout
  app.post('/logout', (c) async {
    c.variables.deleteCookie('session_id');
    return c.json({'message': 'Logged out'});
  });

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
  print('Server running on http://localhost:8080');
}

String generateSessionId() {
  return DateTime.now().millisecondsSinceEpoch.toString();
}
```

## Security Best Practices

1. **Use `httpOnly` for sensitive cookies**
   ```dart
   CookieOptions(
     httpOnly: true, // Prevents XSS attacks
   )
   ```

2. **Always use `secure` in production**
   ```dart
   CookieOptions(
     secure: Platform.environment['ENV'] == 'production',
   )
   ```

3. **Set `sameSite` to prevent CSRF**
   ```dart
   CookieOptions(
     sameSite: SameSite.lax, // or .strict
   )
   ```

4. **Use short `maxAge` for sensitive data**
   ```dart
   CookieOptions(
     maxAge: Duration(hours: 1), // Session expires quickly
   )
   ```

5. **Combine security options**
   ```dart
   CookieOptions(
     httpOnly: true,
     secure: true,
     sameSite: SameSite.strict,
     maxAge: Duration(days: 1),
   )
   ```

## Next Steps

- Learn about [JWT Authentication](/server/auth/jwt) for stateless auth
- Explore [Basic Auth](/server/auth/basic-auth) for simple authentication
- Read about [Security best practices](/server/concepts/middleware#security)
