---
title: Static Files Middleware - Aim Framework
description: Serve static files securely in Dart. HTML, CSS, JavaScript, images with MIME types, caching, and SPA support.
head:
  - - meta
    - name: keywords
      content: Dart static files, serve static, MIME types, SPA support, Aim static middleware
---

# Static Files

Serve static files (HTML, CSS, JavaScript, images, etc.) with built-in security.

## Installation

```bash
dart pub add aim_server_static
```

## Quick Start

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_static/aim_server_static.dart';

void main() async {
  final app = Aim();

  // Serve files from 'public' directory
  app.use(serveStatic(root: 'public'));

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
}
```

Directory structure:
```
public/
  ├── index.html
  ├── styles.css
  ├── script.js
  └── images/
      └── logo.png
```

Access files:
- `http://localhost:8080/index.html`
- `http://localhost:8080/styles.css`
- `http://localhost:8080/images/logo.png`

## Configuration

### Custom Root Directory

```dart
app.use(serveStatic(root: 'assets'));
app.use(serveStatic(root: 'dist'));
```

### Path Prefix

Serve static files under a specific path:

```dart
app.use(serveStatic(
  root: 'public',
  prefix: '/static',
));
```

Access: `http://localhost:8080/static/index.html`

### Index Files

Automatically serve index files:

```dart
app.use(serveStatic(
  root: 'public',
  index: 'index.html', // Default
));
```

Request to `/` serves `/index.html`

## Complete Example

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_static/aim_server_static.dart';

void main() async {
  final app = Aim();

  // Serve static files
  app.use(serveStatic(
    root: 'public',
    index: 'index.html',
  ));

  // API routes
  app.get('/api/data', (c) async {
    return c.json({'message': 'API response'});
  });

  // Fallback for SPA (Single Page Application)
  app.notFound((c) async {
    final indexFile = File('public/index.html');
    if (await indexFile.exists()) {
      final content = await indexFile.readAsString();
      return c.html(content);
    }
    return c.json({'error': 'Not Found'}, statusCode: 404);
  });

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
  print('Server running on http://localhost:8080');
}
```

## MIME Types

The middleware automatically sets correct `Content-Type` headers:

| Extension | MIME Type |
|-----------|-----------|
| `.html` | `text/html` |
| `.css` | `text/css` |
| `.js` | `application/javascript` |
| `.json` | `application/json` |
| `.png` | `image/png` |
| `.jpg`, `.jpeg` | `image/jpeg` |
| `.gif` | `image/gif` |
| `.svg` | `image/svg+xml` |
| `.pdf` | `application/pdf` |
| `.txt` | `text/plain` |

## Security Features

The middleware includes built-in security:

1. **Path traversal prevention** - Blocks `../` attempts
2. **Hidden file protection** - Blocks files starting with `.`
3. **Safe path resolution** - Validates all paths

## Directory Listing

::: warning
Directory listing is **disabled by default** for security. Files must be accessed by exact path.
:::

## SPA Support

For Single Page Applications (React, Vue, etc.):

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_static/aim_server_static.dart';

void main() async {
  final app = Aim();

  // Serve static assets
  app.use(serveStatic(root: 'dist'));

  // API routes
  app.get('/api/*', apiHandler);

  // SPA fallback - serve index.html for unmatched routes
  app.notFound((c) async {
    final indexFile = File('dist/index.html');
    final content = await indexFile.readAsString();
    return c.html(content);
  });

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
}
```

## Multiple Static Directories

```dart
// Serve from multiple directories
app.use(serveStatic(root: 'public'));
app.use(serveStatic(root: 'assets', prefix: '/assets'));
app.use(serveStatic(root: 'uploads', prefix: '/uploads'));
```

## Caching

Add cache headers for performance:

```dart
app.use((c, next) async {
  if (c.req.path.startsWith('/static/')) {
    c.header('Cache-Control', 'public, max-age=31536000'); // 1 year
  }
  return next();
});

app.use(serveStatic(root: 'public', prefix: '/static'));
```

## Example Project Structure

```
my_app/
  ├── bin/
  │   └── server.dart
  ├── public/
  │   ├── index.html
  │   ├── css/
  │   │   └── style.css
  │   ├── js/
  │   │   └── app.js
  │   └── images/
  │       └── logo.png
  └── pubspec.yaml
```

`public/index.html`:
```html
<!DOCTYPE html>
<html>
  <head>
    <title>My App</title>
    <link rel="stylesheet" href="/css/style.css">
  </head>
  <body>
    <h1>Welcome</h1>
    <img src="/images/logo.png" alt="Logo">
    <script src="/js/app.js"></script>
  </body>
</html>
```

## Best Practices

1. **Separate static and dynamic routes**
   ```dart
   app.use(serveStatic(root: 'public', prefix: '/static'));
   app.get('/api/*', apiHandler);
   ```

2. **Use versioned assets**
   ```html
   <link rel="stylesheet" href="/css/style.v1.2.3.css">
   ```

3. **Set cache headers**
   ```dart
   c.header('Cache-Control', 'public, max-age=31536000');
   ```

4. **Compress assets** (gzip, brotli) before serving

5. **Use CDN for production** - Consider CloudFlare, AWS CloudFront

## Testing

```bash
# Serve files
curl http://localhost:8080/index.html

# With prefix
curl http://localhost:8080/static/style.css

# Check MIME type
curl -I http://localhost:8080/logo.png
```

## Security Considerations

1. **Never serve source code**
   ```dart
   // Don't serve from project root
   app.use(serveStatic(root: '.')); // ❌ Bad

   // Serve from specific directory
   app.use(serveStatic(root: 'public')); // ✅ Good
   ```

2. **Block sensitive files**
   - `.env` files
   - Configuration files
   - Database files
   - Source code

3. **Use HTTPS in production**

4. **Set security headers**
   ```dart
   c.header('X-Content-Type-Options', 'nosniff');
   c.header('X-Frame-Options', 'DENY');
   ```

## Next Steps

- Learn about [Multipart](/server/middleware/multipart) for file uploads
- Explore [CORS](/server/middleware/cors) for cross-origin requests
- Read about [Security best practices](/server/concepts/middleware#security)
