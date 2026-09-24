import 'dart:async';
import 'dart:io';

import 'package:bench_runner/process.dart';
import 'package:test/test.dart';

void main() {
  test('waitUntilReady returns once the server answers 200', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    var ready = false;
    server.listen((req) async {
      req.response.statusCode = ready ? 200 : 503;
      await req.response.close();
    });
    Future<void>.delayed(const Duration(milliseconds: 50), () => ready = true);
    final elapsed = await waitUntilReady(
      Uri.parse('http://127.0.0.1:${server.port}/'),
      interval: const Duration(milliseconds: 5),
    );
    expect(elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 40)));
  });

  test('waitUntilReady times out when nothing listens', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close();
    expect(
      () => waitUntilReady(
        Uri.parse('http://127.0.0.1:$port/'),
        timeout: const Duration(milliseconds: 200),
        interval: const Duration(milliseconds: 20),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('residentSetKb reads this process', () async {
    final rss = await residentSetKb(pid);
    expect(rss, isNotNull);
    expect(rss!, greaterThan(1000));
  });

  test('residentSetKb is null for a pid that does not exist', () async {
    expect(await residentSetKb(999999), isNull);
  });

  test('runStep throws on a non-zero exit', () async {
    expect(
      () => runStep(['false'], workingDirectory: Directory.current),
      throwsA(isA<ProcessException>()),
    );
  });
}
