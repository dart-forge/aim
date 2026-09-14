## 0.2.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.2.0)

## 0.1.1

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.1.1)


## 0.1.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/v0.1.0)


## 0.0.1

Initial release - CORS middleware extracted from `aim_server`

### Features

- **Origin validation**: Flexible origin control with string, list, or custom function
- **Method restrictions**: Specify allowed HTTP methods
- **Header control**: Control request and response headers
- **Credentials support**: Support for credentials (cookies, authorization headers)
- **Preflight requests**: Automatic handling of OPTIONS requests
- **Cache control**: Configure cache duration for preflight responses

### Examples

```dart
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_cors/aim_server_cors.dart';

final app = Aim();

// Allow all origins (default)
app.use(cors());

// Allow specific origin
app.use(cors(CorsOptions(
  origin: 'https://example.com',
  credentials: true,
)));

// Allow multiple origins
app.use(cors(CorsOptions(
  origin: ['https://example.com', 'https://app.example.com'],
)));

// Custom origin validation
app.use(cors(CorsOptions(
  origin: (String origin) => origin.endsWith('.example.com'),
)));
```