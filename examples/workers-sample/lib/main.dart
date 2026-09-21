import 'dart:convert';

import 'package:aim_workers/aim_workers.dart';
import 'package:aim_server_cors/aim_server_cors.dart';

void main() {
  final app = Aim();

  app.use(cors());

  app.get('/', (c) async => c.text('Hello from Dart on workerd'));

  app.get('/users/:id', (c) async => c.json({'id': c.param('id')}));

  app.post('/echo', (c) async {
    final body = await c.req.json();
    return c.json({'echo': body});
  });

  app.get('/headers', (c) async => c.json(c.headers));

  app.get('/cookies', (c) async {
    c.header('set-cookie', 'a=1; Path=/\nb=2; Path=/');
    return c.text('cookies set');
  });

  app.get('/sse', (c) async {
    final events = Stream<int>.periodic(
      const Duration(milliseconds: 100),
      (i) => i,
    ).take(3).map((i) => utf8.encode('data: tick $i\n\n'));
    return c.stream(
      events,
      headers: {
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
      },
    );
  });

  app.get('/env', (c) async {
    return c.text(c.env?.string('GREETING') ?? 'GREETING is not set');
  });

  app.get('/boom', (c) async => throw StateError('boom'));

  app.get('/not-modified', (c) async {
    c.header('etag', '"v1"');
    return c.text('', statusCode: 304);
  });

  app.get('/cf', (c) async {
    final cf = c.cf;
    return c.json({
      'country': cf?.country,
      'colo': cf?.colo,
      'city': cf?.city,
      'asn': cf?.asn,
      'latitude': cf?.latitude,
    });
  });

  app.notFound((c) async => c.json({'error': 'not found'}, statusCode: 404));

  app.onError((error, c) async {
    return c.json({'error': error.toString()}, statusCode: 500);
  });

  app.serveWorkers();
}
