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

/// Answers 404 for the first [notFoundCount] requests, then 200.
Future<HttpServer> notFoundThenOkServer(int notFoundCount) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var seen = 0;
  server.listen((req) async {
    if (seen < notFoundCount) {
      seen++;
      req.response.statusCode = 404;
      req.response.write('not found');
      await req.response.close();
      return;
    }
    req.response.write('ok');
    await req.response.close();
  });
  return server;
}

Future<HttpServer> alwaysNotFoundServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    req.response.statusCode = 404;
    req.response.write('not found');
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

  test('coldProbe retries past a brand-new route\'s 404s and returns the first 200', () async {
    final server = await notFoundThenOkServer(2);
    addTearDown(server.close);
    final probe = await coldProbe(
      Uri.parse('http://127.0.0.1:${server.port}/'),
      interval: const Duration(milliseconds: 10),
    );
    expect(probe.notFoundRetries, 2);
    expect(probe.ttfb, isA<Duration>());
  });

  test('coldProbe throws when the target never stops answering 404', () async {
    final server = await alwaysNotFoundServer();
    addTearDown(server.close);
    expect(
      () => coldProbe(
        Uri.parse('http://127.0.0.1:${server.port}/'),
        timeout: const Duration(milliseconds: 300),
        interval: const Duration(milliseconds: 50),
      ),
      throwsA(isA<StateError>().having((e) => e.toString(), 'message', contains('404'))),
    );
  });

  test('coldProbe throws on a non-404, non-200 answer', () async {
    final server = await slowServer(Duration.zero);
    addTearDown(server.close);
    expect(() => coldProbe(Uri.parse('http://127.0.0.1:${server.port}/fail')), throwsStateError);
  });
}
