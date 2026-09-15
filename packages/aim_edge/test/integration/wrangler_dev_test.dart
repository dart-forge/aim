@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Path of examples/edge-sample relative to packages/aim_edge (the CWD of
/// `dart test`).
const _exampleDir = '../../examples/edge-sample';

int? _port;
Process? _wrangler;
HttpClient? _client;

/// The ephemeral port `wrangler dev` is listening on. Only valid once
/// `setUpAll` has assigned it; used by the `get()` helper and the tests.
int get port => _port!;

/// The shared HTTP client. Only valid once `setUpAll` has assigned it.
HttpClient get client => _client!;

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<void> _waitUntilReady(HttpClient client, int port) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final req = await client.getUrl(Uri.parse('http://localhost:$port/'));
      final res = await req.close();
      await res.drain<void>();
      if (res.statusCode == 200) return;
    } catch (_) {
      // not up yet
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw StateError('wrangler dev did not become ready on port $port');
}

/// Returns every descendant PID of [pid] (not including [pid] itself),
/// ordered depth-first with children before their parents (i.e. deepest
/// descendants first). Must be called while [pid] and its tree are still
/// alive: `npx wrangler dev` forks a chain of processes (npm exec -> node
/// wrangler-dist/cli.js -> workerd), and once the root process exits its
/// children are reparented to init and no longer appear under
/// `pgrep -P <root pid>` — enumerating after signalling the root would miss
/// them and let wrangler/workerd survive undetected.
Future<List<int>> _descendantPids(int pid) async {
  final result = await Process.run('pgrep', ['-P', '$pid']);
  final children = (result.stdout as String)
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .map(int.parse);
  final descendants = <int>[];
  for (final child in children) {
    // Best-effort: a process forked between this pgrep call and its
    // recursive descent (or after the deepest enumeration) can still slip
    // through this snapshot.
    descendants.addAll(await _descendantPids(child));
    descendants.add(child);
  }
  return descendants;
}

void main() {
  final wranglerOutput = StringBuffer();

  setUpAll(() async {
    final build = await Process.run(Platform.resolvedExecutable, [
      'run',
      '../../packages/aim_cli/bin/aim.dart',
      'build',
    ], workingDirectory: _exampleDir);
    expect(
      build.exitCode,
      equals(0),
      reason: 'build failed:\n${build.stdout}\n${build.stderr}',
    );

    _port = await _freePort();
    _wrangler = await Process.start('npx', [
      '--yes',
      'wrangler@4',
      'dev',
      '--port',
      '$port',
      '--log-level',
      'error',
    ], workingDirectory: _exampleDir);
    _wrangler!.stdout.transform(utf8.decoder).listen(wranglerOutput.write);
    _wrangler!.stderr.transform(utf8.decoder).listen(wranglerOutput.write);

    _client = HttpClient();
    try {
      await _waitUntilReady(client, port);
    } catch (e) {
      fail('$e\nwrangler output:\n$wranglerOutput');
    }
  });

  tearDownAll(() async {
    _client?.close(force: true);

    final wrangler = _wrangler;
    if (wrangler != null) {
      // Enumerate and kill descendants BEFORE signalling the root: if the
      // root exits first, its children are reparented and a subsequent
      // `pgrep -P <root pid>` finds nothing, leaving wrangler/workerd alive.
      final descendants = await _descendantPids(wrangler.pid);
      for (final pid in descendants) {
        await Process.run('kill', ['-9', '$pid']);
      }
      wrangler.kill(ProcessSignal.sigkill);
      await wrangler.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => -1,
      );
    }

    // Last-resort fallback: whatever is still listening on the dev port.
    final p = _port;
    if (p != null) {
      await Process.run('sh', [
        '-c',
        'lsof -ti tcp:$p | xargs kill -9 2>/dev/null; true',
      ]);
    }
  });

  Future<HttpClientResponse> get(
    String path, {
    Map<String, String>? headers,
  }) async {
    final req = await client.getUrl(Uri.parse('http://localhost:$port$path'));
    headers?.forEach(req.headers.set);
    return req.close();
  }

  test('serves text', () async {
    final res = await get('/');
    expect(res.statusCode, 200);
    expect(await utf8.decodeStream(res), 'Hello from Dart on workerd');
  });

  test('routes path parameters to JSON', () async {
    final res = await get('/users/42');
    expect(res.statusCode, 200);
    expect(res.headers.contentType?.mimeType, 'application/json');
    expect(jsonDecode(await utf8.decodeStream(res)), {'id': '42'});
  });

  test('reads a JSON request body', () async {
    final req = await client.postUrl(Uri.parse('http://localhost:$port/echo'));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'a': 1, 'b': 'two'}));
    final res = await req.close();
    expect(res.statusCode, 200);
    expect(jsonDecode(await utf8.decodeStream(res)), {
      'echo': {'a': 1, 'b': 'two'},
    });
  });

  test('exposes request headers', () async {
    final res = await get('/headers', headers: {'x-probe': 'yes'});
    final body = jsonDecode(await utf8.decodeStream(res)) as Map;
    expect(body['x-probe'], 'yes');
  });

  test('sends multiple Set-Cookie headers', () async {
    final res = await get('/cookies');
    await res.drain<void>();
    expect(res.headers['set-cookie'], hasLength(2));
    expect(res.headers['set-cookie'], contains('a=1; Path=/'));
    expect(res.headers['set-cookie'], contains('b=2; Path=/'));
  });

  test('applies the cors middleware', () async {
    final res = await get('/', headers: {'origin': 'https://example.com'});
    await res.drain<void>();
    expect(res.headers.value('access-control-allow-origin'), '*');
  });

  test('answers a CORS preflight with 204 and no body', () async {
    final req = await client.openUrl(
      'OPTIONS',
      Uri.parse('http://localhost:$port/echo'),
    );
    req.headers.set('origin', 'https://example.com');
    req.headers.set('access-control-request-method', 'POST');
    final res = await req.close();
    final body = await utf8.decodeStream(res);
    expect(res.statusCode, 204);
    expect(res.headers.value('access-control-allow-origin'), '*');
    expect(body, isEmpty);
  });

  test('sends 304 without a body even after middleware set headers',
      () async {
    final res = await get('/not-modified');
    final body = await utf8.decodeStream(res);
    expect(res.statusCode, 304);
    expect(res.headers.value('etag'), '"v1"');
    expect(body, isEmpty);
  });

  test('reads worker bindings through c.env', () async {
    final res = await get('/env');
    expect(await utf8.decodeStream(res), 'hello from workerd');
  });

  test('exposes request.cf as typed properties', () async {
    final res = await get('/cf');
    expect(res.statusCode, 200);
    final body = jsonDecode(await utf8.decodeStream(res)) as Map;
    expect(body['country'], isA<String>().having((s) => s.length, 'length', 2));
    expect(body['colo'], isA<String>().having((s) => s.isNotEmpty, 'non-empty', isTrue));
    expect(body['asn'], anyOf(isNull, isA<int>()));
    expect(body['latitude'], anyOf(isNull, isA<num>()));
  });

  test('uses the custom 404 handler', () async {
    final res = await get('/nope');
    expect(res.statusCode, 404);
    expect(jsonDecode(await utf8.decodeStream(res)), {'error': 'not found'});
  });

  test('uses the custom error handler', () async {
    final res = await get('/boom');
    expect(res.statusCode, 500);
    final body = jsonDecode(await utf8.decodeStream(res)) as Map;
    expect(body['error'], contains('boom'));
  });

  test('streams SSE events instead of buffering them', () async {
    final res = await get('/sse');
    expect(res.headers.contentType?.mimeType, 'text/event-stream');

    final arrivals = <DateTime>[];
    final chunks = <String>[];
    await for (final chunk in res.transform(utf8.decoder)) {
      arrivals.add(DateTime.now());
      chunks.add(chunk);
    }

    final text = chunks.join();
    expect(text, contains('data: tick 0'));
    expect(text, contains('data: tick 2'));
    expect(
      arrivals.length,
      greaterThanOrEqualTo(2),
      reason: 'events arrived in a single chunk: $text',
    );
    final spread = arrivals.last.difference(arrivals.first);
    expect(
      spread,
      greaterThan(const Duration(milliseconds: 100)),
      reason: 'events were buffered and flushed together',
    );
  });
}
