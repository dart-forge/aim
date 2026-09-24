import 'dart:io';

import 'package:bench_runner/oha.dart';
import 'package:bench_runner/scenarios.dart';
import 'package:test/test.dart';

OhaResult _resultWith({
  required double successRate,
  required Map<String, int> statusCodes,
}) => OhaResult(
  requestsPerSec: 1,
  p50Ms: 1,
  p99Ms: 1,
  successRate: successRate,
  statusCodes: statusCodes,
);

void main() {
  test('parseOha reads rps, latency percentiles and status codes', () {
    final json = File('test/fixtures/oha.json').readAsStringSync();
    final result = parseOha(json);
    expect(result.requestsPerSec, 51234.5);
    expect(result.p50Ms, 1.1);
    expect(result.p99Ms, 3.4);
    expect(result.successRate, 1.0);
    expect(result.statusCodes, {'200': 512345});
  });

  test('parseOha names the missing top-level field', () {
    expect(
      () => parseOha('{}'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('metrics'),
        ),
      ),
    );
  });

  test('parseOha names the missing nested field', () {
    expect(
      () => parseOha('{"metrics":{"success_rate":1,"requests_per_sec":1}}'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('latency_ms'),
        ),
      ),
    );
  });

  test('ohaArguments for a GET scenario', () {
    final args = ohaArguments(
      scenarios[0],
      Uri.parse('http://127.0.0.1:18080'),
      duration: const Duration(seconds: 10),
      connections: 64,
    );
    expect(args, [
      '-z', '10s', '-c', '64', '--no-tui', '--output-format', 'json',
      'http://127.0.0.1:18080/',
    ]);
  });

  test('allOk is true when every status code is 200', () {
    expect(
      allOk(_resultWith(successRate: 1, statusCodes: const {'200': 10})),
      isTrue,
    );
  });

  test('allOk is false when some requests got a non-200', () {
    expect(
      allOk(
        _resultWith(
          successRate: 1,
          statusCodes: const {'200': 9, '500': 1},
        ),
      ),
      isFalse,
    );
  });

  test('allOk is false when every request got the same non-200 code', () {
    expect(
      allOk(_resultWith(successRate: 1, statusCodes: const {'404': 10})),
      isFalse,
    );
  });

  test('allOk is false when the success rate is below 1 even if the only '
      'status code seen is 200', () {
    expect(
      allOk(_resultWith(successRate: 0.9, statusCodes: const {'200': 9})),
      isFalse,
    );
  });

  test('ohaArguments for the POST scenario sends the json body', () {
    final args = ohaArguments(
      scenarios[2],
      Uri.parse('http://127.0.0.1:18080'),
      duration: const Duration(seconds: 3),
      connections: 8,
    );
    expect(args, [
      '-z', '3s', '-c', '8', '--no-tui', '--output-format', 'json',
      '-m', 'POST',
      '-H', 'Content-Type: application/json',
      '-d', '{"name":"Aim","tags":["a","b"],"count":3}',
      'http://127.0.0.1:18080/json',
    ]);
  });
}
