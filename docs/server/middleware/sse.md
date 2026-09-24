---
title: SSE Middleware - Aim Framework
description: Server-Sent Events for real-time streaming in Dart. Live feeds, notifications, and progress updates with auto-reconnect.
head:
  - - meta
    - name: keywords
      content: Dart SSE, Server-Sent Events, real-time streaming, live updates, event streaming, Aim SSE middleware
---

# Server-Sent Events (SSE)

Real-time server-to-client event streaming using Server-Sent Events, via an
extension method on `Context` — no middleware to register.

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
  final app = Aim();

  app.get('/events', (c) async {
    return c.sse((stream) async {
      for (var i = 0; i < 10; i++) {
        await Future.delayed(Duration(seconds: 1));
        stream.send('Event $i');
      }
    });
  });

  await app.serve(host: InternetAddress.anyIPv4, port: 8080);
}
```

`sse()` is an extension method on `Context` — there is no `sse()` middleware,
nothing to add with `app.use()`, and no `Variables` subclass to type the app
with. The connection closes automatically when the callback returns, throws,
or the client disconnects.

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
  return c.sse((stream) async {
    stream.send('Hello, SSE!');
  });
});
```

### Multiple Events

```dart
app.get('/events', (c) async {
  return c.sse((stream) async {
    for (var i = 0; i < 5; i++) {
      await Future.delayed(Duration(seconds: 1));
      stream.send('Event number $i');
    }
  });
});
```

### JSON Events

`sendJson` encodes its argument with `jsonEncode` for you:

```dart
app.get('/events', (c) async {
  return c.sse((stream) async {
    stream.sendJson({
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
  return c.sse((stream) async {
    // Different event types
    stream.sendJson({'message': 'New notification'}, event: 'notification');
    stream.sendJson({'status': 'completed'}, event: 'update');
  });
});
```

### Events with ID

```dart
app.get('/events', (c) async {
  return c.sse((stream) async {
    var id = 0;
    while (true) {
      await Future.delayed(Duration(seconds: 1));
      id++;
      stream.send('Event $id', id: '$id');
    }
  });
});
```

## Keep-Alive

Send periodic keep-alive comments to prevent connection timeout — `keepAlive()`
sends an empty comment for you:

```dart
import 'dart:async';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_sse/aim_server_sse.dart';

app.get('/events', (c) async {
  return c.sse((stream) async {
    // Keep-alive every 30 seconds
    final keepAliveTimer = Timer.periodic(
      Duration(seconds: 30),
      (_) => stream.keepAlive(),
    );

    try {
      // Your event logic
      while (true) {
        await Future.delayed(Duration(minutes: 1));
        stream.send('Update');
      }
    } finally {
      keepAliveTimer.cancel();
    }
  });
});
```

## Comments

Send comments (not visible to client):

```dart
app.get('/events', (c) async {
  return c.sse((stream) async {
    stream.comment('This is a comment');
    stream.comment('Connection established at ${DateTime.now()}');
  });
});
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
import 'dart:convert';
import 'package:http/http.dart' as http;

final request = http.Request('GET', Uri.parse('http://localhost:8080/events'));
final response = await request.send();

await for (final chunk in response.stream.transform(utf8.decoder)) {
  print('Received: $chunk');
}
```

## Complete Examples

### Live Counter

There's no callback for "the client disconnected" — cleanup runs when your
own callback decides to stop, so tie it to a `finally` block:

```dart
import 'dart:async';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_sse/aim_server_sse.dart';

app.get('/counter', (c) async {
  return c.sse((stream) async {
    var count = 0;
    final timer = Timer.periodic(Duration(seconds: 1), (_) {
      stream.sendJson({'count': ++count});
    });

    try {
      // Stop after a minute — there is no client-disconnect callback to
      // hook cleanup into, so it's tied to your own stopping condition.
      await Future.delayed(Duration(minutes: 1));
    } finally {
      timer.cancel();
    }
  });
});
```

### Progress Updates

```dart
app.get('/progress', (c) async {
  return c.sse((stream) async {
    for (var i = 0; i <= 100; i += 10) {
      await Future.delayed(Duration(milliseconds: 500));
      stream.sendJson({
        'percentage': i,
        'message': 'Processing... $i%',
      }, event: 'progress');
    }

    stream.sendJson({'message': 'Done!'}, event: 'complete');
  });
});
```

### Live Feed

```dart
import 'dart:async';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_sse/aim_server_sse.dart';

app.get('/feed', (c) async {
  return c.sse((stream) async {
    // Keep-alive so proxies don't time out an idle connection
    final keepAliveTimer = Timer.periodic(
      Duration(seconds: 30),
      (_) => stream.keepAlive(),
    );

    // Stand in for your own live-update source (a database change feed, a
    // queue subscription, and so on)
    final updates = Stream.periodic(
      Duration(seconds: 5),
      (i) => {'id': '$i', 'type': 'update', 'message': 'Update #$i'},
    );

    final subscription = updates.listen((update) {
      stream.sendJson(update, id: update['id'], event: update['type']);
    });

    try {
      await Future.delayed(Duration(minutes: 5));
    } finally {
      keepAliveTimer.cancel();
      await subscription.cancel();
    }
  });
});
```

### User-Specific Notifications

`sse()` works on any `Context<E>`, so it composes with a middleware that
does need `Variables` — [JWT auth](/server/auth/jwt), say, to scope the feed
to the signed-in user:

```dart
import 'dart:io';
import 'package:aim_server/aim_server.dart';
import 'package:aim_server_jwt/aim_server_jwt.dart';
import 'package:aim_server_sse/aim_server_sse.dart';

final app = Aim<JwtVariables>(
  variablesFactory: () => JwtVariables.create(
    JwtOptions(
      algorithm: HS256(
        secretKey: SecretKey(secret: 'your-secret-key-at-least-32-chars'),
      ),
    ),
  ),
);

app.use(jwt());

app.get('/notifications', (c) async {
  final userId = c.variables.jwtPayload['sub']; // Set by the JWT middleware

  return c.sse((stream) async {
    // Stand in for your own per-user notification source
    final updates = Stream.periodic(
      Duration(seconds: 10),
      (i) => {'message': 'Notification #$i for $userId'},
    );

    final subscription = updates.listen((notification) {
      stream.sendJson(notification, event: 'notification');
    });

    try {
      await Future.delayed(Duration(minutes: 10));
    } finally {
      await subscription.cancel();
    }
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
   import 'dart:async';
   import 'package:aim_server/aim_server.dart';
   import 'package:aim_server_sse/aim_server_sse.dart';

   app.get('/events', (c) async {
     return c.sse((stream) async {
       Timer.periodic(Duration(seconds: 30), (_) {
         stream.keepAlive();
       });
     });
   });
   ```

2. **Clean up in a `finally` block**

   There is no callback for "the client disconnected" — the stream closes
   automatically when your callback returns, throws, or the connection
   drops, so cancel timers and subscriptions where you'd naturally stop:
   ```dart
   import 'dart:async';
   import 'package:aim_server/aim_server.dart';
   import 'package:aim_server_sse/aim_server_sse.dart';

   app.get('/events', (c) async {
     return c.sse((stream) async {
       final timer = Timer.periodic(Duration(seconds: 30), (_) => stream.keepAlive());

       try {
         for (var i = 0; i < 5; i++) {
           await Future.delayed(Duration(seconds: 1));
           stream.send('tick $i');
         }
       } finally {
         timer.cancel();
       }
     });
   });
   ```

3. **Use event IDs for resumption**
   ```dart
   app.get('/events', (c) async {
     return c.sse((stream) async {
       var messageId = 0;
       while (true) {
         await Future.delayed(Duration(seconds: 1));
         messageId++;
         stream.send('Message $messageId', id: '$messageId');
       }
     });
   });
   ```

4. **Send JSON for structured data**
   ```dart
   app.get('/events', (c) async {
     return c.sse((stream) async {
       stream.sendJson({
         'type': 'update',
         'payload': {'progress': 42},
       });
     });
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

- Explore [Middleware patterns](/server/concepts/middleware)
- Read about [Context streaming](/server/concepts/context#stream-response)
