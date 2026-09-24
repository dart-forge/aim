import 'package:aim_workers/aim_workers.dart';

const routeCount = 100;

void main() {
  final app = Aim();
  app.get('/', (c) async => c.text('Hello, World!'));
  app.get('/users/:id', (c) async => c.json({'id': c.param('id'), 'name': c.query['name']}));
  app.post('/json', (c) async => c.json(await c.req.json()));
  for (var i = 1; i <= routeCount; i++) {
    final name = 'item${i.toString().padLeft(3, '0')}';
    app.get('/r/$name', (c) async => c.text(name));
  }
  app.serveWorkers();
}
