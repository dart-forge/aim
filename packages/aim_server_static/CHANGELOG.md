## 0.3.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.3.0)

## 0.2.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.2.0)

## 0.1.1

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.1.1)


## 0.1.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/v0.1.0)


## 0.0.1

Initial release - Static file serving for Aim framework

### Features

- **Directory serving**: Serve entire directories with `serveStatic()` middleware
- **Path traversal protection**: Built-in security against `../` attacks
- **Dotfile protection**: Prevent access to sensitive hidden files (`.env`, `.git`, etc.)
- **URL prefix matching**: Serve files under specific URL paths with `path` parameter
- **Index file support**: Automatic `index.html` serving for directory requests
- **Single file serving**: Context extension `c.file()` for serving individual files
- **Download support**: Force file downloads with custom filenames
- **MIME type detection**: Automatic content-type headers for common file formats

### Security

- Path normalization and validation to prevent directory traversal
- Dotfile access control with `DotFiles` enum (allow/deny/ignore)
- Absolute path rejection in `c.file()` method
- Safe path joining with the `path` package

### Examples

```dart
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_static/aim_server_static.dart';

final app = Aim();

// Basic static file serving
app.use(serveStatic('./public'));

// With URL prefix and index file
app.use(serveStatic('./public',
  path: '/static',
  index: 'index.html',
  dotFiles: DotFiles.deny,
));

// Single file serving
app.get('/download', (c) => c.file('docs/manual.pdf', download: true));
```
