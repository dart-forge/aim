import 'dart:io';

import 'package:bench_runner/oha.dart';
import 'package:bench_runner/scenarios.dart';
import 'package:test/test.dart';

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
