## 0.3.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.3.0)

## 0.2.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.2.0)

## 0.1.1

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.1.1)


## 0.1.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/v0.1.0)


## 0.0.1

Initial release - HTTP logging middleware for Aim framework

### Features

- Request logging with HTTP method and path
- Response logging with status code and response time
- Customizable `onRequest` callback for custom request logging
- Customizable `onResponse` callback for custom response logging
- Automatic response time measurement in milliseconds
- Easy integration with custom logging systems

### Examples

```dart
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_logger/aim_server_logger.dart';

final app = Aim();

// Basic logging
app.use(logger());

// Custom callbacks
app.use(logger(
  onRequest: (c) async {
    print('Incoming: ${c.req.method} ${c.req.uri.path}');
  },
  onResponse: (c, durationMs) async {
    print('Outgoing: ${c.response?.statusCode} (${durationMs}ms)');
  },
));
```
