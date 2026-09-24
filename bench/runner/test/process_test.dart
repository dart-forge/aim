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

  test('ensurePortFree throws while the port is bound, completes once free',
      () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await expectLater(
      () => ensurePortFree(port),
      throwsA(isA<StateError>()),
    );
    await server.close();
    await expectLater(ensurePortFree(port), completes);
  });

  test('memoryFootprintKb reads this process', () async {
    final kb = await memoryFootprintKb(pid);
    expect(kb, isNotNull);
    expect(kb!, greaterThan(1000));
  });

  test('memoryFootprintKb is null for a pid that does not exist', () async {
    expect(await memoryFootprintKb(999999), isNull);
  });

  test('parseFootprintKb reads the KB value from the header line', () {
    expect(
      parseFootprintKb(
        'zsh [9328]: 64-bit    Footprint: 1664 KB (16384 bytes per page)',
      ),
      1664,
    );
    expect(parseFootprintKb('Footprint: 45.2 MB'), 46285);
    expect(parseFootprintKb('no header'), isNull);
  });

  test('runStep throws on a non-zero exit', () async {
    expect(
      () => runStep(['false'], workingDirectory: Directory.current),
      throwsA(isA<ProcessException>()),
    );
  });

  test('discardOutput drains stdout so a big write never blocks', () async {
    // 300 KB is larger than a typical 64 KB pipe buffer; without draining,
    // the child's write() would block once the buffer fills and this
    // process.exitCode would never complete, tripping the timeout below.
    // (The negative control — asserting that it *does* hang without
    // discardOutput — is intentionally not a test: a hung test hangs CI.)
    final process = await Process.start(
      'sh',
      ['-c', 'head -c 300000 /dev/zero'],
    );
    discardOutput(process);
    expect(await process.exitCode.timeout(const Duration(seconds: 5)), 0);
  });

  test('runCapturing returns stdout and stderr, and names the exit code on failure', () async {
    final out = await runCapturing(['sh', '-c', 'echo out; echo err 1>&2'], workingDirectory: Directory.current);
    expect(out, contains('out'));
    expect(out, contains('err'));
    await expectLater(
      runCapturing(['sh', '-c', 'echo boom 1>&2; exit 3'], workingDirectory: Directory.current),
      throwsA(isA<ProcessException>().having((e) => e.message, 'message', contains('boom'))),
    );
  });
}
