import 'dart:convert';
import 'dart:io';

import 'package:relic/relic.dart';

const routeCount = 100;

Future<void> main() async {
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final app = RelicApp()
    ..get('/', _hello)
    ..get('/users/:id', _user)
    ..post('/json', _echoJson);
  for (var i = 1; i <= routeCount; i++) {
    final name = 'item${i.toString().padLeft(3, '0')}';
    app.get('/r/$name', (Request request) {
      return Response.ok(body: Body.fromString(name));
    });
  }

  await app.serve(address: InternetAddress.loopbackIPv4, port: port);
}

Response _hello(Request request) {
  return Response.ok(body: Body.fromString('Hello, World!'));
}

Response _user(Request request) {
  final body = jsonEncode({
    'id': request.rawPathParameters[#id],
    'name': request.url.queryParameters['name'],
  });
  return Response.ok(body: Body.fromString(body, mimeType: MimeType.json));
}

Future<Response> _echoJson(Request request) async {
  final raw = await request.readAsString();
  return Response.ok(
    body: Body.fromString(jsonEncode(jsonDecode(raw)), mimeType: MimeType.json),
  );
}
