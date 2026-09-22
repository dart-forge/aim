import 'package:aim_workers/aim_workers.dart';

void main() {
  final app = Aim();

  app.get('/', (c) async => c.text('Hello from Dart on workerd'));

  app.get('/users/:id', (c) async => c.json({'id': c.param('id')}));

  // Vars and secrets from wrangler.jsonc, and resource bindings such as KV.
  app.get(
    '/greeting',
    (c) async => c.text(c.env?.string('GREETING') ?? '(unset)'),
  );

  app.serveWorkers();
}
