import 'dart:io';

import 'package:aim_server/aim_server.dart';

const routeCount = 100;

Future<void> main() async {
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final app = Aim();

  app.get('/', (c) async => c.text('Hello, World!'));
  app.get('/users/:id', (c) async {
    return c.json({'id': c.param('id'), 'name': c.query['name']});
  });
  app.post('/json', (c) async => c.json(await c.req.json()));
  for (var i = 1; i <= routeCount; i++) {
    final name = 'item$i';
    app.get('/r/$name', (c) async => c.text(name));
  }

  await app.serve(host: InternetAddress.loopbackIPv4, port: port);
}
