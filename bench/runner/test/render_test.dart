import 'package:bench_runner/oha.dart';
import 'package:bench_runner/render.dart';
import 'package:bench_runner/results.dart';
import 'package:test/test.dart';

void main() {
  final results = BenchResults(
    label: 'm4',
    timestamp: DateTime.utc(2026, 9, 24, 12),
    environment: {
      'os': 'macOS 26.0',
      'arch': 'arm64',
      'cpu': 'Apple M4 Pro',
      'cores': 12,
      'memoryBytes': 51539607552,
      'dart': 'Dart SDK version: 3.13.0 (stable)',
    },
    settings: {
      'durationSeconds': 10,
      'connections': 64,
      'runs': 5,
      'oha': 'oha 1.16.0',
    },
    apps: [
      AppResult(
        name: 'dart_io',
        versions: const {},
        binaryBytes: 5 * 1024 * 1024,
        startupMs: 11,
        memoryKb: 30 * 1024,
        scenarios: [
          ScenarioResult.fromRuns('plaintext', [
            const OhaResult(
              requestsPerSec: 123456.7,
              p50Ms: 0.51,
              p99Ms: 1.234,
              successRate: 1,
              statusCodes: {'200': 1},
            ),
          ]),
        ],
      ),
    ],
  );

  test('renders an environment section and one table per scenario', () {
    final md = renderMarkdown(results);
    expect(md, contains('Apple M4 Pro'));
    expect(md, contains('Dart SDK version: 3.13.0'));
    expect(md, contains('### plaintext'));
    expect(md, contains('| dart_io |'));
    expect(md, contains('123,457'));
    expect(md, contains('0.51'));
    expect(md, contains('1.23'));
  });

  test('renders startup, memory and binary size', () {
    final md = renderMarkdown(results);
    expect(md, contains('| dart_io | 11 | 30.0 | 5.0 |'));
  });

  test('uses no comparative adjectives', () {
    final md = renderMarkdown(results).toLowerCase();
    for (final word in ['fastest', 'blazing', 'faster than']) {
      expect(md, isNot(contains(word)));
    }
  });

  test('renders no "Not measured" section when nothing was skipped', () {
    final md = renderMarkdown(results);
    expect(md, isNot(contains('### Not measured')));
  });

  test('renders a "Not measured" section listing skipped apps', () {
    final withSkipped = BenchResults(
      label: results.label,
      timestamp: results.timestamp,
      environment: results.environment,
      settings: results.settings,
      apps: results.apps,
      skipped: const [SkippedApp('relic', 'success rate 0.9 ({"200": 900})')],
    );
    final md = renderMarkdown(withSkipped);
    expect(md, contains('### Not measured'));
    expect(md, contains('- relic: success rate 0.9 ({"200": 900})'));
  });
}
