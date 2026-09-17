---
title: Cookie Middleware - Aim Framework
description: Secure cookie management for Dart servers. HttpOnly, Secure, SameSite, and expiration settings for safe session handling.
head:
  - - meta
    - name: keywords
      content: Dart cookie, HttpOnly, Secure cookie, SameSite, session management, Aim cookie middleware
---

# Cookie

Secure cookie management for Aim, via extension methods on `Context` — no
middleware to register.

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
  final app = Aim();

  app.get('/set', (c) async {
    c.setCookie('session_id', 'abc123');
    return c.text('Cookie set');
  });

  app.get('/get', (c) async {
    final sessionId = c.getCookie('session_id');
    return c.text('Session: $sessionId');
  });

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
}
```

`setCookie`, `getCookie`, `cookies`, and `deleteCookie` are all extension
methods on `Context`. There is no `cookie()` middleware and nothing to add
with `app.use()` — importing the package is enough to use them on any `c`.

## Setting Cookies

### Basic Cookie

```dart
c.setCookie('user_id', '123');
```

### With Options

```dart
c.setCookie(
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
c.setCookie(
  'auth_token',
  'secret-token',
  options: CookieOptions(
    httpOnly: true,   // Prevent JavaScript access
    secure: true,     // HTTPS only
    sameSite: SameSite.strict,
  ),
);
```

### Values with special characters

The cookie value is percent-encoded when it is written and decoded again
when it is read back through `getCookie` or `cookies`, so a value
containing `;`, `,`, whitespace, or a quote round-trips intact:

```dart
c.setCookie('message', 'hello world; thanks!');
// Set-Cookie: message=hello%20world%3B%20thanks%21
```

The cookie *name* is written as given and is not encoded — keep it to the
characters the `Set-Cookie` specification allows for a cookie name.

## Getting Cookies

`getCookie` returns the value of one cookie from the request's `Cookie`
header, or `null` if the request didn't send it:

```dart
app.get('/profile', (c) async {
  final userId = c.getCookie('user_id');

  if (userId == null) {
    return c.json({'error': 'Not logged in'}, statusCode: 401);
  }

  return c.json({'userId': userId});
});
```

`cookies` returns every cookie on the request as a `Map<String, String>`:

```dart
app.get('/debug/cookies', (c) async {
  return c.json(c.cookies);
});
```

## Deleting Cookies

```dart
app.get('/logout', (c) async {
  c.deleteCookie('session_id');
  c.deleteCookie('user_id');
  return c.text('Logged out');
});
```

`deleteCookie` sets the cookie's value to empty with `Max-Age=0`. If the
cookie was set with a `path` or `domain`, pass the same ones to
`deleteCookie` — a browser only clears a cookie whose path and domain
match:

```dart
c.deleteCookie('session_id', path: '/', domain: '.example.com');
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
  final app = Aim();

  // Login
  app.post('/login', (c) async {
    final body = await c.req.json();
    final username = body['username'];
    final password = body['password'];

    // Validate credentials...
    if (username == 'admin' && password == 'password') {
      // Set secure session cookie
      c.setCookie(
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
      c.setCookie(
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
    final sessionId = c.getCookie('session_id');

    if (sessionId == null) {
      return c.json({'error': 'Not authenticated'}, statusCode: 401);
    }

    // Validate session...
    final theme = c.getCookie('theme') ?? 'light';

    return c.json({
      'username': 'admin',
      'theme': theme,
    });
  });

  // Logout
  app.post('/logout', (c) async {
    c.deleteCookie('session_id');
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
