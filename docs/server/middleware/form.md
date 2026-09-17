---
title: Form Data Middleware - Aim Framework
description: Parse HTML form data in Dart. Handle application/x-www-form-urlencoded POST requests with ease.
head:
  - - meta
    - name: keywords
      content: Dart form data, form parsing, x-www-form-urlencoded, HTML forms, Aim form middleware
---

# Form Data

Parse `application/x-www-form-urlencoded` form data, via an extension method
on `Request` — no middleware to register.

## Installation

```bash
dart pub add aim_server_form
```

## Quick Start

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_form/aim_server_form.dart';

void main() async {
  final app = Aim();

  app.post('/login', (c) async {
    final form = await c.req.formData();
    final username = form['username'];
    final password = form['password'];

    return c.json({
      'username': username,
      'password': password,
    });
  });

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
}
```

`formData()` is an extension method on `Request`. There is no `form()`
middleware and nothing to add with `app.use()` — importing the package is
enough to call it on any `c.req`.

## Form Data

`await c.req.formData()` returns a `FormData` with the same field-access
methods as a `Map`:

```dart
app.post('/submit', (c) async {
  final form = await c.req.formData();

  final name = form['name'];
  final email = form['email'];
  final message = form['message'];

  return c.json({
    'name': name,
    'email': email,
    'message': message,
  });
});
```

`get` takes an optional default, `has` checks whether a key was submitted at
all, and `keys`/`values`/`entries`/`toMap()` give you the whole thing:

```dart
app.post('/submit', (c) async {
  final form = await c.req.formData();

  final remember = form.get('remember', 'false');
  final hasEmail = form.has('email');

  return c.json({
    'remember': remember,
    'hasEmail': hasEmail,
    'fields': form.toMap(),
  });
});
```

## Complete Example

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_form/aim_server_form.dart';

void main() async {
  final app = Aim();

  // Login form
  app.get('/login', (c) async {
    return c.html('''
      <!DOCTYPE html>
      <html>
        <body>
          <form method="POST" action="/login">
            <input type="text" name="username" placeholder="Username">
            <input type="password" name="password" placeholder="Password">
            <button type="submit">Login</button>
          </form>
        </body>
      </html>
    ''');
  });

  // Handle login
  app.post('/login', (c) async {
    final form = await c.req.formData();
    final username = form['username'];
    final password = form['password'];

    // Validate credentials...
    if (username == 'admin' && password == 'password') {
      return c.html('<h1>Welcome, $username!</h1>');
    }

    return c.html('<h1>Invalid credentials</h1>', statusCode: 401);
  });

  // Contact form
  app.post('/contact', (c) async {
    final form = await c.req.formData();
    final name = form['name'];
    final email = form['email'];
    final message = form['message'];

    // Process form...
    print('Contact from $name ($email): $message');

    return c.json({
      'status': 'success',
      'message': 'Thank you for your message!',
    });
  });

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
  print('Server running on http://localhost:8080');
}
```

## HTML Form Example

```html
<form method="POST" action="/submit">
  <input type="text" name="username">
  <input type="email" name="email">
  <textarea name="message"></textarea>
  <button type="submit">Submit</button>
</form>
```

## Testing with curl

```bash
curl -X POST http://localhost:8080/login \
  -d "username=admin&password=secret"
```

## Content Type

`formData()` only parses requests with:

```
Content-Type: application/x-www-form-urlencoded
```

Anything else — a missing header, `multipart/form-data`, JSON — throws a
`FormatException`:

```dart
app.post('/submit', (c) async {
  try {
    final form = await c.req.formData();
    return c.json(form.toMap());
  } on FormatException catch (e) {
    return c.json({'error': e.message}, statusCode: 400);
  }
});
```

For file uploads, use the [Multipart middleware](/server/middleware/multipart) instead.

## Next Steps

- Learn about [Multipart](/server/middleware/multipart) for file uploads
- Explore [Cookie](/server/middleware/cookie) for session management
- Read about [Request handling](/server/concepts/context#request-body)
