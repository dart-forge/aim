/// How a scenario's response body is compared.
enum BodyKind { text, json }

/// One request every app must answer identically.
class Scenario {
  const Scenario({
    required this.id,
    required this.method,
    required this.path,
    required this.kind,
    required this.expected,
    this.requestBody,
  });

  final String id;
  final String method;

  /// Path and query, without scheme or host.
  final String path;

  /// Sent as the request body with `Content-Type: application/json`.
  final String? requestBody;
  final BodyKind kind;

  /// A [String] for [BodyKind.text], a decoded JSON value for [BodyKind.json].
  final Object expected;
}

/// Number of static routes `/r/item001` .. `/r/item100` every app
/// registers, zero-padded to 3 digits so lexicographic order (the order
/// dart_frog's file-based routing registers routes in) matches
/// registration order; the last one is the request in [scenarios].
const int routeCount = 100;

const List<Scenario> scenarios = [
  Scenario(
    id: 'plaintext',
    method: 'GET',
    path: '/',
    kind: BodyKind.text,
    expected: 'Hello, World!',
  ),
  Scenario(
    id: 'params_json',
    method: 'GET',
    path: '/users/42?name=aim',
    kind: BodyKind.json,
    expected: {'id': '42', 'name': 'aim'},
  ),
  Scenario(
    id: 'post_json',
    method: 'POST',
    path: '/json',
    requestBody: '{"name":"Aim","tags":["a","b"],"count":3}',
    kind: BodyKind.json,
    expected: {
      'name': 'Aim',
      'tags': ['a', 'b'],
      'count': 3,
    },
  ),
  Scenario(
    id: 'routes_100',
    method: 'GET',
    path: '/r/item100',
    kind: BodyKind.text,
    expected: 'item100',
  ),
];
