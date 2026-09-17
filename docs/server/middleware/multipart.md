---
title: Multipart & File Upload - Aim Framework
description: Handle file uploads in Dart. Parse multipart/form-data, validate files, and implement secure upload endpoints.
head:
  - - meta
    - name: keywords
      content: Dart file upload, multipart form data, file validation, upload handler, Aim multipart middleware
---

# Multipart Form Data

Handle file uploads and multipart form data (`multipart/form-data`).

## Installation

```bash
dart pub add aim_server_multipart
```

## Quick Start

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_multipart/aim_server_multipart.dart';

void main() async {
  final app = Aim<MultipartVariables>(
    variablesFactory: () => MultipartVariables(),
  );

  app.use(multipart());

  app.post('/upload', (c) async {
    final files = c.variables.files;
    final file = files['avatar'];

    if (file != null) {
      await File('uploads/${file.filename}').writeAsBytes(file.bytes);
      return c.json({'uploaded': file.filename});
    }

    return c.json({'error': 'No file uploaded'}, statusCode: 400);
  });

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
}
```

## File Upload

Access uploaded files through `c.variables.files`:

```dart
app.post('/upload', (c) async {
  final files = c.variables.files;
  final file = files['document']; // Field name from form

  if (file != null) {
    print('Filename: ${file.filename}');
    print('Content-Type: ${file.contentType}');
    print('Size: ${file.bytes.length} bytes');

    // Save file
    await File('uploads/${file.filename}').writeAsBytes(file.bytes);
  }

  return c.json({'success': true});
});
```

## Form Fields

Access form fields through `c.variables.formData`:

```dart
app.post('/upload', (c) async {
  final title = c.variables.formData['title'];
  final description = c.variables.formData['description'];
  final file = c.variables.files['document'];

  return c.json({
    'title': title,
    'description': description,
    'filename': file?.filename,
  });
});
```

## Multiple Files

Handle multiple file uploads:

```dart
app.post('/gallery', (c) async {
  final files = c.variables.files.values; // All uploaded files

  for (final file in files) {
    await File('uploads/${file.filename}').writeAsBytes(file.bytes);
  }

  return c.json({
    'uploaded': files.length,
    'files': files.map((f) => f.filename).toList(),
  });
});
```

## Configuration

### Max File Size

```dart
app.use(multipart(
  maxFileSize: 10 * 1024 * 1024, // 10 MB
));
```

### Max Files

```dart
app.use(multipart(
  maxFileSize: 5 * 1024 * 1024,  // 5 MB per file
  maxFiles: 10,                   // Maximum 10 files
));
```

## Complete Example

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_multipart/aim_server_multipart.dart';

void main() async {
  final app = Aim<MultipartVariables>(
    variablesFactory: () => MultipartVariables(),
  );

  // Configure multipart
  app.use(multipart(
    maxFileSize: 10 * 1024 * 1024, // 10 MB
  ));

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
    final title = c.variables.formData['title'];
    final description = c.variables.formData['description'];
    final file = c.variables.files['document'];

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
    final filepath = 'uploads/${DateTime.now().millisecondsSinceEpoch}_${file.filename}';
    await File(filepath).writeAsBytes(file.bytes);

    return c.json({
      'success': true,
      'title': title,
      'description': description,
      'filename': file.filename,
      'size': file.bytes.length,
      'type': file.contentType,
    });
  });

  // Multiple files
  app.post('/gallery', (c) async {
    final files = c.variables.files.values;

    if (files.isEmpty) {
      return c.json({'error': 'No files uploaded'}, statusCode: 400);
    }

    await Directory('uploads').create(recursive: true);

    final uploaded = <String>[];
    for (final file in files) {
      final filepath = 'uploads/${DateTime.now().millisecondsSinceEpoch}_${file.filename}';
      await File(filepath).writeAsBytes(file.bytes);
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
  <input type="file" name="image1">
  <input type="file" name="image2">
  <input type="file" name="image3">
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
  -F "image1=@/path/to/photo1.jpg" \
  -F "image2=@/path/to/photo2.jpg"
```

## File Object

The `MultipartFile` object contains:

| Property | Type | Description |
|----------|------|-------------|
| `filename` | `String` | Original filename |
| `contentType` | `String` | MIME type (e.g., `image/jpeg`) |
| `bytes` | `List<int>` | File contents |

## Validation Example

```dart
app.post('/upload', (c) async {
  final file = c.variables.files['document'];

  if (file == null) {
    return c.json({'error': 'No file'}, statusCode: 400);
  }

  // Check file size
  if (file.bytes.length > 5 * 1024 * 1024) {
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
  await File('uploads/${file.filename}').writeAsBytes(file.bytes);

  return c.json({'success': true});
});
```

## Security Best Practices

1. **Validate file types**
   ```dart
   if (!file.contentType.startsWith('image/')) {
     return c.json({'error': 'Only images'}, statusCode: 400);
   }
   ```

2. **Set max file size**
   ```dart
   app.use(multipart(maxFileSize: 5 * 1024 * 1024));
   ```

3. **Sanitize filenames**
   ```dart
   final safeName = file.filename.replaceAll(RegExp(r'[^a-zA-Z0-9.]'), '_');
   ```

4. **Use unique filenames**
   ```dart
   final filename = '${DateTime.now().millisecondsSinceEpoch}_${file.filename}';
   ```

5. **Store outside web root**
   ```dart
   await File('../uploads/${filename}').writeAsBytes(file.bytes);
   ```

## Next Steps

- Learn about [Form Data](/server/middleware/form) for simple forms
- Explore [Static Files](/server/middleware/static) for serving uploads
- Read about [File handling](/server/concepts/context#file-response)
