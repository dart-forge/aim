import 'dart:io';

import 'package:bench_runner/cloud/probe.dart';
import 'package:test/test.dart';

Future<HttpServer> slowServer(Duration delay) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    await Future<void>.delayed(delay);
    if (req.uri.path == '/fail') req.response.statusCode = 500;
    req.response.write('ok');
    await req.response.close();
  });
  return server;
}

void main() {
  test('timeToFirstByte is at least the server delay', () async {
    final server = await slowServer(const Duration(milliseconds: 40));
    addTearDown(server.close);
    final d = await timeToFirstByte(Uri.parse('http://127.0.0.1:${server.port}/'));
    expect(d, greaterThanOrEqualTo(const Duration(milliseconds: 40)));
  });

  test('sequentialLatencies returns one duration per request', () async {
    final server = await slowServer(Duration.zero);
    addTearDown(server.close);
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final ds = await sequentialLatencies(Uri.parse('http://127.0.0.1:${server.port}/'), 5, client: client);
    expect(ds, hasLength(5));
  });

  test('a non-200 answer throws', () async {
    final server = await slowServer(Duration.zero);
    addTearDown(server.close);
    expect(() => timeToFirstByte(Uri.parse('http://127.0.0.1:${server.port}/fail')), throwsStateError);
  });
}
