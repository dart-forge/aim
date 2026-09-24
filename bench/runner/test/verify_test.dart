import 'dart:convert';
import 'dart:io';

import 'package:bench_runner/verify.dart';
import 'package:test/test.dart';

/// Serves the four scenarios correctly, except where [broken] overrides.
/// When [prefix] is set, it is stripped from the incoming path before
/// routing, mimicking a Supabase function served under a base path.
Future<HttpServer> serveFake({
  Map<String, String> broken = const {},
  String prefix = '',
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final res = req.response;
    var path = req.uri.path;
    if (path.startsWith(prefix)) {
      path = path.substring(prefix.length);
    }
    String body;
    if (req.method == 'GET' && path == '/') {
      body = broken['/'] ?? 'Hello, World!';
    } else if (req.method == 'GET' && path == '/users/42') {
      body = broken['/users/42'] ??
          jsonEncode({'name': req.uri.queryParameters['name'], 'id': '42'});
    } else if (req.method == 'POST' && path == '/json') {
      final raw = await utf8.decoder.bind(req).join();
      body = broken['/json'] ?? jsonEncode(jsonDecode(raw));
    } else if (req.method == 'GET' && path == '/r/item100') {
      body = broken['/r/item100'] ?? 'item100';
    } else {
      res.statusCode = 404;
      body = 'not found';
    }
    res.write(body);
    await res.close();
  });
  return server;
}

void main() {
  test('a correct app has no mismatches', () async {
    final server = await serveFake();
    addTearDown(server.close);
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    expect(await verifyApp(base), isEmpty);
  });

  test('json bodies are compared structurally, not textually', () async {
    // The fake emits {"name":..,"id":..} — reversed key order still matches.
    final server = await serveFake();
    addTearDown(server.close);
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    final mismatches = await verifyApp(base);
    expect(mismatches.where((m) => m.scenarioId == 'params_json'), isEmpty);
  });

  test('a wrong text body is reported with the scenario id', () async {
    final server = await serveFake(broken: {'/': 'hello'});
    addTearDown(server.close);
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    final mismatches = await verifyApp(base);
    expect(mismatches, hasLength(1));
    expect(mismatches.single.scenarioId, 'plaintext');
    expect(mismatches.single.message, contains('hello'));
  });

  test('a wrong json body is reported', () async {
    final server = await serveFake(broken: {'/json': '{"name":"x"}'});
    addTearDown(server.close);
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    final mismatches = await verifyApp(base);
    expect(mismatches.map((m) => m.scenarioId), ['post_json']);
  });

  test('a base path is kept for every scenario', () async {
    final server = await serveFake(prefix: '/functions/v1/f');
    addTearDown(server.close);
    final base = Uri.parse('http://127.0.0.1:${server.port}/functions/v1/f');
    expect(await verifyApp(base), isEmpty);
  });

  test('a non-200 status is reported', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((req) async {
      req.response.statusCode = 500;
      await req.response.close();
    });
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    final mismatches = await verifyApp(base);
    expect(mismatches, hasLength(4));
    expect(mismatches.first.message, contains('500'));
  });
}
