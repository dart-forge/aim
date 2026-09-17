---
title: SSE Middleware - Aim Framework
description: Server-Sent Events for real-time streaming in Dart. Live feeds, notifications, and progress updates with auto-reconnect.
head:
  - - meta
    - name: keywords
      content: Dart SSE, Server-Sent Events, real-time streaming, live updates, event streaming, Aim SSE middleware
---

# Server-Sent Events (SSE)

Real-time server-to-client event streaming using Server-Sent Events.

## Installation

```bash
dart pub add aim_server_sse
```

## Quick Start

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_sse/aim_server_sse.dart';

void main() async {
  final app = Aim<SseVariables>(
    variablesFactory: () => SseVariables(),
  );

  app.use(sse());

  app.get('/events', (c) async {
    return c.sse((sink) async {
      for (var i = 0; i < 10; i++) {
        await Future.delayed(Duration(seconds: 1));
        sink.sendEvent(data: 'Event $i');
      }
    });
  });

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
}
```

## What is SSE?

Server-Sent Events (SSE) is a standard for pushing data from server to client over HTTP. Unlike WebSocket, SSE is:

- **Unidirectional**: Server → Client only
- **Text-based**: Uses HTTP/1.1
- **Auto-reconnect**: Browsers automatically reconnect
- **Event-driven**: Named events with IDs

Perfect for:
- Live feeds (news, social media)
- Real-time notifications
- Progress updates
- Live dashboards
- Stock tickers

## Sending Events

### Basic Event

```dart
app.get('/events', (c) async {
  return c.sse((sink) async {
    sink.sendEvent(data: 'Hello, SSE!');
  });
});
```

### Multiple Events

```dart
app.get('/events', (c) async {
  return c.sse((sink) async {
    for (var i = 0; i < 5; i++) {
      await Future.delayed(Duration(seconds: 1));
      sink.sendEvent(data: 'Event number $i');
    }
  });
});
```

### JSON Events

```dart
app.get('/events', (c) async {
  return c.sse((sink) async {
    sink.sendEvent(data: {
      'type': 'notification',
      'message': 'New message',
      'timestamp': DateTime.now().toIso8601String(),
    });
  });
});
```

### Named Events

```dart
app.get('/events', (c) async {
  return c.sse((sink) async {
    // Different event types
    sink.sendEvent(
      event: 'notification',
      data: {'message': 'New notification'},
    );

    sink.sendEvent(
      event: 'update',
      data: {'status': 'completed'},
    );
  });
});
```

### Events with ID

```dart
app.get('/events', (c) async {
  return c.sse((sink) async {
    var id = 0;
    while (true) {
      await Future.delayed(Duration(seconds: 1));
      sink.sendEvent(
        id: '${++id}',
        data: 'Event $id',
      );
    }
  });
});
```

## Keep-Alive

Send periodic keep-alive messages to prevent connection timeout:

```dart
app.get('/events', (c) async {
  return c.sse((sink) async {
    // Keep-alive every 30 seconds
    final keepAlive = Timer.periodic(
      Duration(seconds: 30),
      (_) => sink.sendComment('keep-alive'),
    );

    try {
      // Your event logic
      while (true) {
        await Future.delayed(Duration(minutes: 1));
        sink.sendEvent(data: 'Update');
      }
    } finally {
      keepAlive.cancel();
    }
  });
});
```

## Comments

Send comments (not visible to client):

```dart
sink.sendComment('This is a comment');
sink.sendComment('Connection established at ${DateTime.now()}');
```

## Client Side

### JavaScript

```javascript
const eventSource = new EventSource('/events');

// Listen to default events
eventSource.onmessage = (event) => {
  console.log('Data:', event.data);
};

// Listen to named events
eventSource.addEventListener('notification', (event) => {
  const data = JSON.parse(event.data);
  console.log('Notification:', data.message);
});

// Handle errors
eventSource.onerror = (error) => {
  console.error('SSE error:', error);
};

// Close connection
// eventSource.close();
```

### Dart

```dart
import 'package:http/http.dart' as http;

final request = http.Request('GET', Uri.parse('http://localhost:8080/events'));
final response = await request.send();

await for (final chunk in response.stream.transform(utf8.decoder)) {
  print('Received: $chunk');
}
```

## Complete Examples

### Live Counter

```dart
app.get('/counter', (c) async {
  return c.sse((sink) async {
    var count = 0;
    final timer = Timer.periodic(Duration(seconds: 1), (_) {
      sink.sendEvent(data: {'count': ++count});
    });

    // Clean up when client disconnects
    sink.onClose = () {
      timer.cancel();
      print('Client disconnected');
    };
  });
});
```

### Progress Updates

```dart
app.get('/progress', (c) async {
  return c.sse((sink) async {
    for (var i = 0; i <= 100; i += 10) {
      await Future.delayed(Duration(milliseconds: 500));
      sink.sendEvent(
        event: 'progress',
        data: {
          'percentage': i,
          'message': 'Processing... $i%',
        },
      );
    }

    sink.sendEvent(
      event: 'complete',
      data: {'message': 'Done!'},
    );
  });
});
```

### Live Feed

```dart
app.get('/feed', (c) async {
  return c.sse((sink) async {
    // Keep-alive
    final keepAlive = Timer.periodic(
      Duration(seconds: 30),
      (_) => sink.sendComment('keep-alive'),
    );

    // Subscribe to real-time updates
    final subscription = feedService.stream.listen((update) {
      sink.sendEvent(
        id: update.id,
        event: update.type,
        data: update.toJson(),
      );
    });

    sink.onClose = () {
      keepAlive.cancel();
      subscription.cancel();
    };
  });
});
```

### Chat Notifications

```dart
class ChatVariables extends SseVariables {
  String? userId;
}

final app = Aim<ChatVariables>(
  variablesFactory: () => ChatVariables(),
);

app.use(sse());

app.get('/notifications', (c) async {
  final userId = c.variables.userId; // Set by auth middleware

  return c.sse((sink) async {
    // Subscribe to user-specific notifications
    final subscription = notificationService
        .streamForUser(userId)
        .listen((notification) {
      sink.sendEvent(
        event: 'notification',
        data: notification.toJson(),
      );
    });

    sink.onClose = () {
      subscription.cancel();
    };
  });
});
```

## Event Format

SSE events follow this format:

```
event: notification
id: 123
data: {"message":"Hello"}
data: {"timestamp":"2024-01-01T00:00:00.000Z"}

```

Multiple `data:` lines are concatenated with newlines.

## Best Practices

1. **Implement keep-alive**
   ```dart
   Timer.periodic(Duration(seconds: 30), (_) {
     sink.sendComment('keep-alive');
   });
   ```

2. **Clean up resources**
   ```dart
   sink.onClose = () {
     timer.cancel();
     subscription.cancel();
   };
   ```

3. **Use event IDs for resumption**
   ```dart
   sink.sendEvent(
     id: messageId,
     data: message,
   );
   ```

4. **Handle client disconnects**
   ```dart
   sink.onClose = () {
     print('Client disconnected: ${c.req.path}');
     // Clean up resources
   };
   ```

5. **Send JSON for structured data**
   ```dart
   sink.sendEvent(data: {
     'type': 'update',
     'payload': {...},
   });
   ```

## SSE vs WebSocket

| Feature | SSE | WebSocket |
|---------|-----|-----------|
| **Direction** | Server → Client | Bidirectional |
| **Protocol** | HTTP/1.1 | ws:// |
| **Auto-reconnect** | ✅ Yes | ❌ No |
| **Complexity** | Simple | More complex |
| **Browser support** | ✅ All modern | ✅ All modern |
| **Best for** | Live feeds, notifications | Chat, gaming, collaboration |

## Browser Support

SSE is supported in all modern browsers:
- Chrome/Edge ✅
- Firefox ✅
- Safari ✅
- Opera ✅

Not supported:
- Internet Explorer ❌

## Next Steps

- Learn about WebSocket support (coming soon)
- Explore [Middleware patterns](/server/concepts/middleware)
- Read about [Context streaming](/server/concepts/context#stream-response)
