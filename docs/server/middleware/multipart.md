---
title: Multipart & File Upload - Aim Framework
description: Handle file uploads in Dart. Parse multipart/form-data, validate files, and implement secure upload endpoints.
head:
  - - meta
    - name: keywords
      content: Dart file upload, multipart form data, file validation, upload handler, Aim multipart middleware
---

# Multipart Form Data

Handle file uploads and multipart form data (`multipart/form-data`), via an
extension method on `Request` — no middleware to register.

## Installation

```bash
dart pub add aim_server_multipart
```

## Quick Start

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_multipart/aim_server_multipart.dart';
import 'package:aim_server_multipart/aim_server_multipart_io.dart';

void main() async {
  final app = Aim();

  app.post('/upload', (c) async {
    final form = await c.req.multipart();
    final file = form.file('avatar');

    if (file != null) {
      await file.saveTo('uploads/${file.filename}');
      return c.json({'uploaded': file.filename});
    }

    return c.json({'error': 'No file uploaded'}, statusCode: 400);
  });

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
}
```

`multipart()` is an extension method on `Request` — there is no `multipart()`
middleware, nothing to add with `app.use()`, and no `Variables` subclass to
type the app with. `saveTo` lives in the separate
`aim_server_multipart_io.dart` import because it touches the file system and
isn't available when compiling to WebAssembly.

## File Upload

`await c.req.multipart()` returns a `MultipartFormData`. Get one file by its
field name with `.file(name)`:

```dart
app.post('/upload', (c) async {
  final form = await c.req.multipart();
  final file = form.file('document'); // Field name from the form

  if (file != null) {
    print('Filename: ${file.filename}');
    print('Content-Type: ${file.contentType}');
    print('Size: ${file.size} bytes');

    // Save file
    await file.saveTo('uploads/${file.filename}');
  }

  return c.json({'success': true});
});
```

## Form Fields

Text fields sent alongside files are read with `.field(name)`:

```dart
app.post('/upload', (c) async {
  final form = await c.req.multipart();
  final title = form.field('title');
  final description = form.field('description');
  final file = form.file('document');

  return c.json({
    'title': title,
    'description': description,
    'filename': file?.filename,
  });
});
```

## Multiple Files

A single field name with several files (an `<input type="file" multiple>`,
or several `-F` flags with the same name) comes back from `.files(name)` as a
list:

```dart
app.post('/gallery', (c) async {
  final form = await c.req.multipart();
  final files = form.files('images');

  for (final file in files) {
    await file.saveTo('uploads/${file.filename}');
  }

  return c.json({
    'uploaded': files.length,
    'files': files.map((f) => f.filename).toList(),
  });
});
```

## Configuration

`multipart()` takes its limits as arguments on the call itself, not as
middleware configuration:

### Max File Size

```dart
final form = await c.req.multipart(
  maxFileSize: 10 * 1024 * 1024, // 10 MB per file
);
```

### Max Total Size

```dart
final form = await c.req.multipart(
  maxFileSize: 5 * 1024 * 1024,   // 5 MB per file
  maxTotalSize: 20 * 1024 * 1024, // 20 MB across all files and fields
);
```

### Allowed MIME Types

```dart
final form = await c.req.multipart(
  allowedMimeTypes: ['image/*', 'application/pdf'],
);
```

Wildcards like `image/*` match any subtype. Exceeding a limit or sending a
disallowed type throws an `Exception`.

## Complete Example

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_multipart/aim_server_multipart.dart';
import 'package:aim_server_multipart/aim_server_multipart_io.dart';

void main() async {
  final app = Aim();

  // Upload form
  app.get('/upload', (c) async {
    return c.html('''
      <!DOCTYPE html>
      <html>
        <body>
          <h1>Upload File</h1>
          <form method="POST" action="/upload" enctype="multipart/form-data">
            <input type="text" name="title" placeholder="Title"><br>
            <textarea name="description" placeholder="Description"></textarea><br>
            <input type="file" name="document"><br>
            <button type="submit">Upload</button>
          </form>
        </body>
      </html>
    ''');
  });

  // Handle upload
  app.post('/upload', (c) async {
    final form = await c.req.multipart(maxFileSize: 10 * 1024 * 1024); // 10 MB
    final title = form.field('title');
    final description = form.field('description');
    final file = form.file('document');

    if (file == null) {
      return c.json({'error': 'No file uploaded'}, statusCode: 400);
    }

    // Validate file type
    if (!file.contentType.startsWith('image/')) {
      return c.json({'error': 'Only images allowed'}, statusCode: 400);
    }

    // Create uploads directory
    await Directory('uploads').create(recursive: true);

    // Save file
    await file.saveTo('uploads/${file.filename}');

    return c.json({
      'success': true,
      'title': title,
      'description': description,
      'filename': file.filename,
      'size': file.size,
      'type': file.contentType,
    });
  });

  // Multiple files under one field name
  app.post('/gallery', (c) async {
    final form = await c.req.multipart();
    final files = form.files('images');

    if (files.isEmpty) {
      return c.json({'error': 'No files uploaded'}, statusCode: 400);
    }

    await Directory('uploads').create(recursive: true);

    final uploaded = <String>[];
    for (final file in files) {
      await file.saveTo('uploads/${file.filename}');
      uploaded.add(file.filename);
    }

    return c.json({
      'success': true,
      'uploaded': uploaded.length,
      'files': uploaded,
    });
  });

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
  print('Server running on http://localhost:8080');
}
```

## HTML Form Example

### Single File

```html
<form method="POST" action="/upload" enctype="multipart/form-data">
  <input type="text" name="title">
  <input type="file" name="document">
  <button type="submit">Upload</button>
</form>
```

### Multiple Files

```html
<form method="POST" action="/gallery" enctype="multipart/form-data">
  <input type="file" name="images" multiple>
  <button type="submit">Upload Gallery</button>
</form>
```

## Testing with curl

### Single File

```bash
curl -X POST http://localhost:8080/upload \
  -F "title=My Document" \
  -F "document=@/path/to/file.pdf"
```

### Multiple Files

```bash
curl -X POST http://localhost:8080/gallery \
  -F "images=@/path/to/photo1.jpg" \
  -F "images=@/path/to/photo2.jpg"
```

## File Object

The `UploadedFile` object contains:

| Property | Type | Description |
|----------|------|-------------|
| `filename` | `String` | Generated, sanitized filename that's safe to use for storage |
| `originalFilename` | `String?` | Original filename as sent by the client — untrusted, display-only |
| `contentType` | `String` | MIME type (e.g., `image/jpeg`) |
| `bytes` | `List<int>` | File contents |
| `size` | `int` | File size in bytes (`bytes.length`) |

## Validation Example

```dart
app.post('/upload', (c) async {
  final form = await c.req.multipart();
  final file = form.file('document');

  if (file == null) {
    return c.json({'error': 'No file'}, statusCode: 400);
  }

  // Check file size
  if (file.size > 5 * 1024 * 1024) {
    return c.json({'error': 'File too large'}, statusCode: 400);
  }

  // Check file type
  final allowedTypes = ['image/jpeg', 'image/png', 'image/gif'];
  if (!allowedTypes.contains(file.contentType)) {
    return c.json({'error': 'Invalid file type'}, statusCode: 400);
  }

  // Check filename extension
  if (!file.filename.endsWith('.jpg') &&
      !file.filename.endsWith('.png')) {
    return c.json({'error': 'Invalid extension'}, statusCode: 400);
  }

  // Save file
  await file.saveTo('uploads/${file.filename}');

  return c.json({'success': true});
});
```

## Security Best Practices

1. **Validate file types**
   ```dart
   final form = await c.req.multipart();
   final file = form.file('document');

   if (file == null || !file.contentType.startsWith('image/')) {
     return c.json({'error': 'Only images'}, statusCode: 400);
   }

   return c.json({'success': true});
   ```

2. **Set a max file size**
   ```dart
   final form = await c.req.multipart(maxFileSize: 5 * 1024 * 1024);
   ```

3. **Don't trust `originalFilename`**

   `file.filename` is already sanitized and safe to use for storage — a
   generated name like `file_1234567890_abc123de.jpg`, never the string the
   client sent. Use `file.originalFilename` only for display, never to build
   a file path.

4. **Store outside web root**
   ```dart
   final form = await c.req.multipart();
   final file = form.file('document');

   if (file != null) {
     await file.saveTo('../uploads/${file.filename}');
   }

   return c.json({'success': true});
   ```

## Next Steps

- Learn about [Form Data](/server/middleware/form) for simple forms
- Explore [Static Files](/server/middleware/static) for serving uploads
- Read about [File handling](/server/concepts/context#file-response)
