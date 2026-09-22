import 'package:aim_deno/aim_deno.dart';

void main() {
  final app = Aim();

  app.get(
    '/',
    (c) async =>
        c.text('Hello from supabase_sample on Supabase Edge Functions'),
  );

  app.get('/users/:id', (c) async => c.json({'id': c.param('id')}));

  app.get(
    '/env',
    (c) async => c.text(c.env?.string('GREETING') ?? 'GREETING is not set'),
  );

  app.notFound((c) async => c.json({'error': 'not found'}, statusCode: 404));

  app.onError((error, c) async {
    return c.json({'error': error.toString()}, statusCode: 500);
  });

  // Supabase serves this function under /supabase_sample and passes that
  // segment through to the handler; strip it so routes above can be
  // written without it.
  app.serveDeno(basePath: 'supabase_sample');
}
