import 'package:aim_deno/aim_deno.dart';

void main() {
  final app = Aim();

  app.get('/', (c) async => c.text('Hello from Dart on Deno'));

  app.get('/users/:id', (c) async => c.json({'id': c.param('id')}));

  app.get(
    '/greeting',
    (c) async => c.text(c.env?.string('GREETING') ?? '(unset)'),
  );

  // Supabase serves this function under /<function-name> and passes that
  // segment through; Deno Deploy and Netlify Edge do not.
  app.serveDeno(basePath: 'my_api');
}
