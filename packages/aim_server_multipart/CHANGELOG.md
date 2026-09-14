## 0.2.0

- **Breaking:** `UploadedFile.saveTo()` moved to the `UploadedFileIO` extension in `package:aim_server_multipart/aim_server_multipart_io.dart`. Add that import to keep using it.
- `aim_server_multipart.dart` now exports `MultipartFormData`, `UploadedFile`, `parseMultipart`, and the `MultipartRequest` extension (previously only a placeholder was exported).
- Depends on `aim_core` instead of `aim_server`, so it works on every runtime adapter.

## 0.1.1

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.1.1)


## 0.1.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/v0.1.0)


## 0.0.1

Initial release of aim_server_multipart - Multipart form data parser for the Aim framework.

### Features

- **Multipart/Form-Data Parsing**: RFC 7578 compliant parser for handling file uploads and form data
- **File Upload Support**:
  - Single file uploads
  - Multiple file uploads with same field name
  - Mixed text fields and files in same request
- **Security Features**:
  - Automatic filename sanitization to prevent path traversal attacks
  - Random unique filename generation to prevent collisions
  - Original filename preserved for reference
- **Validation Options**:
  - `maxFileSize` - Limit individual file size
  - `maxTotalSize` - Limit total upload size
  - `allowedMimeTypes` - Filter by MIME type with wildcard support (`image/*`)
- **Efficient Processing**:
  - Stream-based processing for memory efficiency
  - Real-time size validation during upload
  - Optimized with `BytesBuilder` for large files
- **Developer Experience**:
  - Type-safe API using Dart 3 Records
  - Clean and intuitive API (`form.file()`, `form.field()`)
  - Comprehensive error handling with `FormatException` and `Exception`
  - Well-documented with examples

### API

- **`MultipartFormData`** class for accessing parsed data
  - `field(String name)` - Get single text field
  - `fields(String name)` - Get multiple fields
  - `file(String name)` - Get single file
  - `files(String name)` - Get multiple files
  - `has(String name)` - Check field/file existence
- **`UploadedFile`** class representing uploaded files
  - `filename` - Sanitized safe filename
  - `originalFilename` - Original client filename
  - `contentType` - MIME type
  - `bytes` - File content
  - `size` - File size
  - `saveTo(String path)` - Save to disk
  - `asString([Encoding])` - Read as string
- **`Request` extension** with `multipart()` method

### Testing

- 39 comprehensive tests covering:
  - Filename sanitization and security
  - File size validation (per-file and total)
  - MIME type filtering with wildcards
  - Multiple files and fields
  - Error handling
  - Edge cases (special characters, Unicode, etc.)

### Supported

- Dart SDK: `^3.10.0`
- Dependencies:
  - `aim_server: ^0.0.6`
  - `mime: ^2.0.0`

### Security Considerations

This package implements several security measures by default:
- Path traversal prevention (blocks `../`, absolute paths)
- Filename sanitization (removes dangerous characters)
- Unique filename generation (prevents overwrites)
- Size limits enforcement
- MIME type validation

### What's Next

Future versions may include:
- Streaming file saves for very large files
- Custom sanitization strategies
- Progress callbacks for upload tracking
- Character encoding detection and conversion
