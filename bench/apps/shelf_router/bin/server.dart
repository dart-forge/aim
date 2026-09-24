import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

const routeCount = 100;
const _text = {'content-type': 'text/plain; charset=utf-8'};
const _json = {'content-type': 'application/json; charset=utf-8'};

Future<void> main() async {
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final router = Router()
    ..get('/', (Request request) => Response.ok('Hello, World!', headers: _text))
    ..get('/users/<id>', (Request request, String id) {
      return Response.ok(
        jsonEncode({'id': id, 'name': request.url.queryParameters['name']}),
        headers: _json,
      );
    })
    ..post('/json', (Request request) async {
      final body = await request.readAsString();
      return Response.ok(jsonEncode(jsonDecode(body)), headers: _json);
    });
  for (var i = 1; i <= routeCount; i++) {
    final name = 'item${i.toString().padLeft(3, '0')}';
    router.get('/r/$name', (Request request) => Response.ok(name, headers: _text));
  }

  await shelf_io.serve(router.call, InternetAddress.loopbackIPv4, port);
}
