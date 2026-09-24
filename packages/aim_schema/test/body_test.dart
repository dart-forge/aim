import 'package:aim_core/aim_core.dart';
import 'package:aim_schema/aim_schema.dart';
import 'package:aim_server_testing/aim_server_testing.dart';
import 'package:test/test.dart';

final createUser = Schema((r) => (name: r.string('name')));

void main() {
  group('c.parse with a body that is not a JSON object', () {
    late TestClient client;

    setUp(() {
      final app = Aim()
        ..use(validationErrorsAsBadRequest())
        ..post('/users', (c) async {
          final body = await c.parse(createUser);
          return c.json({'name': body.name});
        });
      client = TestClient(app);
    });

    // Each of these is the client's mistake. Before, every one of them
    // escaped as a TypeError or FormatException from decoding and reached
    // the error handler as a 500 — a client error logged as a server fault.
    final cases = {
      'a JSON array': '[1, 2]',
      'a JSON string': '"x"',
      'JSON null': 'null',
      'a JSON number': '42',
      'malformed JSON': '{',
      'an empty body': '',
    };

    for (final MapEntry(key: label, value: body) in cases.entries) {
      test('$label is a 400, not a 500', () async {
        final response = await client.post(
          '/users',
          body: body,
          headers: {'content-type': 'application/json'},
        );

        expect(response.statusCode, 400);
        final json = await response.bodyAsJson();
        expect(json['error'], 'Bad Request');
        final details = (json['details'] as List).cast<Map<String, dynamic>>();
        expect(details, hasLength(1));
        // The body as a whole is wrong, so the error is not about any field.
        expect(details.single['path'], '');
        expect(details.single['message'], isNotEmpty);
      });
    }

    test('malformed JSON and a non-object say different things', () async {
      Future<String> messageFor(String body) async {
        final response = await client.post(
          '/users',
          body: body,
          headers: {'content-type': 'application/json'},
        );
        final json = await response.bodyAsJson();
        return ((json['details'] as List).single as Map)['message'] as String;
      }

      // A client fixing its request needs to know which mistake it made.
      expect(await messageFor('{'), contains('not valid JSON'));
      expect(await messageFor('[1, 2]'), contains('must be a JSON object'));
    });

    test('a well-formed object still validates as before', () async {
      final response = await client.post('/users', body: {'name': 'naoki'});
      expect(response.statusCode, 200);
    });
  });
}
