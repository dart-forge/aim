import 'package:aim_core/aim_core.dart';
import 'package:aim_schema/aim_schema.dart';

final userOut = Output<({int id, String name})>(
  (w) => [w.integer('id', (u) => u.id), w.string('name', (u) => u.name)],
);
final userResponses = responses((r) => (ok: r(200, userOut)));

void main() {
  Aim()..get(
    '/u',
    typed(
      responses: userResponses,
      (c, req, res) async => res.ok((id: 'x', name: 'a')),
    ),
  );
}
