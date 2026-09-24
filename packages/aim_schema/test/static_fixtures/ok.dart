import 'package:aim_core/aim_core.dart';
import 'package:aim_schema/aim_schema.dart';

final createUser = Schema((r) => (name: r.string('name')));
final userOut = Output<({int id, String name})>(
  (w) => [w.integer('id', (u) => u.id), w.string('name', (u) => u.name)],
);
final userResponses = responses((r) => (ok: r(200, userOut)));

void main() {
  final app = Aim();
  app.post(
    '/users',
    typed(
      body: createUser,
      responses: userResponses,
      (c, req, res) async => res.ok((id: 1, name: req.body.name)),
    ),
  );
}
