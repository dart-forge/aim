import 'dart:convert';

import 'package:bench_runner/oha.dart';
import 'package:bench_runner/results.dart';
import 'package:test/test.dart';

OhaResult run(double rps, double p50, double p99) => OhaResult(
  requestsPerSec: rps,
  p50Ms: p50,
  p99Ms: p99,
  successRate: 1,
  statusCodes: const {'200': 1},
);

void main() {
  test('ScenarioResult takes the median of each metric independently', () {
    final s = ScenarioResult.fromRuns('plaintext', [
      run(100, 1, 9),
      run(300, 3, 7),
      run(200, 2, 8),
    ]);
    expect(s.medianRps, 200);
    expect(s.medianP50Ms, 2);
    expect(s.medianP99Ms, 8);
  });

  test('BenchResults round-trips through JSON', () {
    final results = BenchResults(
      label: 'test',
      timestamp: DateTime.utc(2026, 9, 24, 12),
      environment: {'os': 'macOS 26.0', 'cores': 12},
      settings: {'durationSeconds': 10, 'connections': 64, 'runs': 5},
      apps: [
        AppResult(
          name: 'aim',
          versions: {'aim_server': '0.4.0 (path)'},
          binaryBytes: 1234,
          startupMs: 12,
          memoryKb: 4567,
          scenarios: [
            ScenarioResult.fromRuns('plaintext', [run(100, 1, 9)]),
          ],
        ),
      ],
    );
    final decoded = BenchResults.fromJson(
      jsonDecode(jsonEncode(results.toJson())) as Map<String, Object?>,
    );
    expect(decoded.label, 'test');
    expect(decoded.timestamp, results.timestamp);
    expect(decoded.environment['cores'], 12);
    expect(decoded.apps.single.name, 'aim');
    expect(decoded.apps.single.memoryKb, 4567);
    expect(decoded.apps.single.scenarios.single.medianRps, 100);
    expect(decoded.apps.single.scenarios.single.runs.single.p99Ms, 9);
  });

  test('skipped apps round-trip through JSON', () {
    final results = BenchResults(
      label: 'test',
      timestamp: DateTime.utc(2026, 9, 24, 12),
      environment: const {},
      settings: const {},
      apps: const [],
      skipped: const [
        SkippedApp('relic', 'success rate 0.9 ({"200": 900, "500": 100})'),
      ],
    );
    final decoded = BenchResults.fromJson(
      jsonDecode(jsonEncode(results.toJson())) as Map<String, Object?>,
    );
    expect(decoded.skipped.single.name, 'relic');
    expect(
      decoded.skipped.single.reason,
      'success rate 0.9 ({"200": 900, "500": 100})',
    );
  });

  test('BenchResults.fromJson defaults skipped to empty when absent', () {
    final decoded = BenchResults.fromJson({
      'label': 'test',
      'timestamp': DateTime.utc(2026, 9, 24, 12).toIso8601String(),
      'environment': <String, Object?>{},
      'settings': <String, Object?>{},
      'apps': <Object?>[],
    });
    expect(decoded.skipped, isEmpty);
  });
}
