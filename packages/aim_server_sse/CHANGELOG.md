## 0.2.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.2.0)

## 0.1.1

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.1.1)


## 0.1.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/v0.1.0)


## 0.0.1

Initial release - Server-Sent Events (SSE) support for Aim framework

### Features

- Server-Sent Events streaming with `c.sse()` extension method
- `SseStream` API with convenient methods:
  - `send()` for sending text events
  - `sendJson()` for sending JSON-encoded events
  - `keepAlive()` for connection keep-alive
  - `comment()` for debug comments
- Support for event types, IDs, and retry intervals
- Automatic connection cleanup on callback completion or error
- Proper SSE protocol formatting with multi-line data support
- Type-safe event handling with `SseEvent` class

### Examples

```dart
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_sse/aim_server_sse.dart';

final app = Aim();

// Basic SSE
app.get('/events', (c) async {
  return c.sse((stream) async {
    stream.send('Hello, SSE!');
    stream.sendJson({'message': 'World!'}, event: 'greeting');
  });
});

// Real-time updates
app.get('/clock', (c) async {
  return c.sse((stream) async {
    while (true) {
      stream.sendJson({'time': DateTime.now().toIso8601String()});
      await Future.delayed(Duration(seconds: 1));
    }
  });
});
```
