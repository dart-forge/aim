import 'package:aim_core/aim_core.dart';
import 'package:aim_schema/aim_schema.dart';
import 'package:aim_server_testing/aim_server_testing.dart';
import 'package:test/test.dart';

final createUser = Schema((r) => (name: r.string('name')));
final idPath = Schema((r) => (id: r.integer('id')));
final dryRun = Schema((r) => (dryRun: r.booleanOrNull('dryRun')));
final userOut = Output<({int id, String name})>(
  (w) => [
    w.integer('id', (u) => u.id),
    w.string('name', (u) => u.name, minLength: 1),
  ],
);
final userResponses = responses((r) => (ok: r(200, userOut)));

void main() {
  test('reads path, query and body and returns the reply as JSON', () async {
    final app = Aim()
      ..put(
        '/users/:id',
        typed(
          path: idPath,
          query: dryRun,
          body: createUser,
          responses: userResponses,
          (c, req, res) async {
            expect(req.query.dryRun, isTrue);
            return res.ok((id: req.path.id, name: req.body.name));
          },
        ),
      );
    final response = await TestClient(app)
        .put('/users/7?dryRun=true', body: {'name': 'naoki'});
    expect(response.statusCode, 200);
    expect(await response.bodyAsJson(), {'id': 7, 'name': 'naoki'});
  });

  test('a bad body becomes 400 via validationErrorsAsBadRequest and skips the handler', () async {
    var called = false;
    final app = Aim()
      ..use(validationErrorsAsBadRequest())
      ..post(
        '/users',
        typed(body: createUser, responses: userResponses, (c, req, res) async {
          called = true;
          return res.ok((id: 1, name: req.body.name));
        }),
      );
    final response = await TestClient(app).post('/users', body: {'name': 3});
    expect(response.statusCode, 400);
    expect(called, isFalse);
  });

  test('a violating reply becomes a 500 whose body names no field', () async {
    final app = Aim()
      ..get(
        '/u',
        typed(
          responses: userResponses,
          (c, req, res) async => res.ok((id: 1, name: '')),
        ),
      );
    final response = await TestClient(app).get('/u');
    expect(response.statusCode, 500);
    expect(await response.bodyAsString(), isNot(contains('name')));
  });

  test('the contract is readable from the handler', () {
    final h = typed(
      body: createUser,
      responses: userResponses,
      (c, req, res) async => res.ok((id: 1, name: 'a')),
    );
    final contract = routeContractOf(h)!;
    expect(contract.body, same(createUser));
    expect(contract.query, isNull);
    expect(contract.responses.single.status, 200);
  });
}
