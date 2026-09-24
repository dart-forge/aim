import 'package:bench_runner/cloud/parsers.dart';
import 'package:bench_runner/cloud/render.dart';
import 'package:bench_runner/cloud/results.dart';
import 'package:bench_runner/results.dart' show SkippedApp;
import 'package:test/test.dart';

CloudResults _results({List<SkippedApp> skipped = const []}) {
  final workersAim = TargetResult.fromMeasurements(
    runtime: 'workers',
    variant: 'aim',
    region: 'nearest Cloudflare colo',
    cycles: [
      ColdCycle(coldMs: 320, warmMedianMs: 28, notFoundRetries: 3),
      ColdCycle(coldMs: 305, warmMedianMs: 27, notFoundRetries: 2),
    ],
    scenarios: [
      ScenarioLatency.fromSamples('plaintext', [20, 22, 21]),
      ScenarioLatency.fromSamples('params_json', [24, 26, 25]),
      ScenarioLatency.fromSamples('post_json', [30, 32, 31]),
      ScenarioLatency.fromSamples('routes_100', [23, 24, 22]),
    ],
    upload: const UploadSize(bytes: 172032, gzipBytes: 49152),
  );
  final workersNative = TargetResult.fromMeasurements(
    runtime: 'workers',
    variant: 'native',
    region: 'nearest Cloudflare colo',
    cycles: [ColdCycle(coldMs: 210, warmMedianMs: 18)],
    scenarios: [
      ScenarioLatency.fromSamples('plaintext', [12, 13, 14]),
      ScenarioLatency.fromSamples('params_json', [15, 16, 17]),
      ScenarioLatency.fromSamples('post_json', [18, 19, 20]),
      ScenarioLatency.fromSamples('routes_100', [14, 15, 16]),
    ],
    upload: const UploadSize(bytes: 8192, gzipBytes: 3072),
  );
  final functionsAim = TargetResult.fromMeasurements(
    runtime: 'functions',
    variant: 'aim',
    region: 'us-central1',
    cycles: [ColdCycle(coldMs: 900, warmMedianMs: 40)],
    scenarios: [
      ScenarioLatency.fromSamples('plaintext', [35, 36, 37]),
      ScenarioLatency.fromSamples('params_json', [38, 39, 40]),
      ScenarioLatency.fromSamples('post_json', [41, 42, 43]),
      ScenarioLatency.fromSamples('routes_100', [37, 38, 39]),
    ],
    upload: const UploadSize(bytes: 5242880),
  );
  final functionsNative = TargetResult.fromMeasurements(
    runtime: 'functions',
    variant: 'native',
    region: 'us-central1',
    cycles: [ColdCycle(coldMs: 700, warmMedianMs: 35)],
    scenarios: [
      ScenarioLatency.fromSamples('plaintext', [30, 31, 32]),
      ScenarioLatency.fromSamples('params_json', [33, 34, 35]),
      ScenarioLatency.fromSamples('post_json', [36, 37, 38]),
      ScenarioLatency.fromSamples('routes_100', [32, 33, 34]),
    ],
    upload: const UploadSize(bytes: 2048),
  );

  return CloudResults(
    label: 'tokyo-office',
    timestamp: DateTime.utc(2026, 9, 24, 12),
    environment: const {
      'os': 'macOS 26.0',
      'arch': 'arm64',
      'cpu': 'Apple M4 Pro',
      'cores': 12,
      'memoryBytes': 51539607552,
      'dart': 'Dart SDK version: 3.13.0 (stable)',
      'wrangler': '4.138.0',
      'supabase': '2.111.0',
      'firebase': '15.30.0',
      'node': 'v22.11.0',
      'aimCommit': 'abc1234',
      'measuredFrom': 'tokyo-office',
    },
    settings: const {
      'cycles': 5,
      'warmAfterCold': 20,
      'requests': 100,
      'pauseBetweenTargetsSeconds': 5,
      'arguments': <String>[],
    },
    targets: [workersAim, workersNative, functionsAim, functionsNative],
    skipped: skipped,
  );
}

void main() {
  final results = _results(
    skipped: const [SkippedApp('supabase/native', 'mismatch on params_json')],
  );

  test('renders the environment, cold start, warm latency and upload sections', () {
    final md = renderCloudMarkdown(results);
    expect(md, contains('## Environment'));
    expect(md, contains('## Cold start'));
    expect(md, contains('## Warm latency'));
    expect(md, contains('## Upload size'));
    expect(md, contains('| workers | aim |'));
    expect(md, contains('(ms)'));
    expect(md, contains('tokyo-office'));
    expect(md, contains('404 retries before first answer (sum)'));
  });

  test('never prints identifying URLs', () {
    final md = renderCloudMarkdown(results);
    expect(md, isNot(contains('workers.dev')));
    expect(md, isNot(contains('run.app')));
    expect(md, isNot(contains('supabase.co')));
  });

  test('notes the Functions upload kind, Dart AOT vs. Node source', () {
    final md = renderCloudMarkdown(results);
    expect(md, contains('AOT bundle'));
    expect(md, contains('source only'));
  });

  test('renders no "Not measured" section when nothing was skipped', () {
    final clean = _results();
    expect(renderCloudMarkdown(clean), isNot(contains('## Not measured')));
  });

  test('sums 404 retries across cycles in the Cold start table', () {
    final md = renderCloudMarkdown(results);
    final row = md.split('\n').firstWhere((line) => line.startsWith('| workers | aim |'));
    expect(row, endsWith('| 5 |'));
  });

  test('lists skipped targets under "Not measured"', () {
    final md = renderCloudMarkdown(results);
    expect(md, contains('## Not measured'));
    expect(md, contains('- supabase/native: mismatch on params_json'));
  });

  test('uses no comparative adjectives', () {
    final md = renderCloudMarkdown(results).toLowerCase();
    for (final word in ['fastest', 'blazing', 'faster than']) {
      expect(md, isNot(contains(word)));
    }
  });
}
