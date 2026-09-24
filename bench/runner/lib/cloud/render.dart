import 'package:bench_runner/cloud/results.dart';
import 'package:bench_runner/scenarios.dart';

/// Markdown for docs: environment, cold start, warm latency (one table per
/// scenario) and upload size. Numbers only — the prose around them is
/// written by hand, after reading them. Never includes a URL: a target is
/// identified by its runtime and variant only, never by the address it was
/// deployed to.
String renderCloudMarkdown(CloudResults r) {
  final b = StringBuffer();
  final env = r.environment;
  final settings = r.settings;

  b.writeln('## Environment');
  b.writeln();
  b.writeln('- Measured from: ${env['measuredFrom'] ?? r.label}');
  final regions = <String, String>{};
  for (final t in r.targets) {
    regions.putIfAbsent(t.runtime, () => t.region);
  }
  for (final entry in regions.entries) {
    b.writeln('- ${entry.key} region: ${entry.value}');
  }
  b.writeln(
    '- Tool versions: wrangler ${env['wrangler']}, supabase ${env['supabase']}, '
    'firebase ${env['firebase']}, node ${env['node']}',
  );
  b.writeln('- Dart: ${env['dart']}');
  if (env['aimCommit'] != null) {
    b.writeln('- Aim commit: ${env['aimCommit']}');
  }
  b.writeln(
    '- ${settings['cycles']} deploy cycles, ${settings['requests']} requests '
    'per scenario.',
  );
  b.writeln(
    '- Runtimes are not compared with each other: each region above is '
    'that runtime\'s own deployment region, and they differ from one '
    'runtime to the next, so a latency difference between runtimes may '
    'reflect network distance rather than the runtime itself.',
  );
  b.writeln();

  b.writeln('## Cold start');
  b.writeln();
  b.writeln('| Runtime | Variant | Cold, median (ms) | Warm right after, median (ms) | Difference (ms) |');
  b.writeln('|---|---|---:|---:|---:|');
  for (final t in r.targets) {
    final diff = t.coldMedianMs - t.warmAfterColdMedianMs;
    b.writeln(
      '| ${t.runtime} | ${t.variant} | ${t.coldMedianMs.toStringAsFixed(0)} | '
      '${t.warmAfterColdMedianMs.toStringAsFixed(0)} | ${diff.toStringAsFixed(0)} |',
    );
  }
  b.writeln();

  b.writeln('## Warm latency');
  b.writeln();
  for (final scenario in scenarios) {
    b.writeln('### ${scenario.id}');
    b.writeln();
    b.writeln('| Runtime | Variant | p50 (ms) | p99 (ms) | min (ms) |');
    b.writeln('|---|---|---:|---:|---:|');
    for (final t in r.targets) {
      final matches = t.scenarios.where((s) => s.scenarioId == scenario.id);
      if (matches.isEmpty) continue;
      final m = matches.single;
      b.writeln(
        '| ${t.runtime} | ${t.variant} | ${m.p50Ms.toStringAsFixed(0)} | '
        '${m.p99Ms.toStringAsFixed(0)} | ${m.minMs.toStringAsFixed(0)} |',
      );
    }
    b.writeln();
  }

  b.writeln('## Upload size');
  b.writeln();
  b.writeln('| Runtime | Variant | Bytes | gzip | Note |');
  b.writeln('|---|---|---:|---:|---|');
  for (final t in r.targets) {
    final note = t.runtime == 'functions' && t.variant == 'aim'
        ? 'AOT bundle'
        : t.runtime == 'functions' && t.variant == 'native'
            ? 'source only'
            : '';
    final gzip = t.upload.gzipBytes?.toString() ?? '?';
    b.writeln('| ${t.runtime} | ${t.variant} | ${t.upload.bytes} | $gzip | $note |');
  }

  if (r.skipped.isNotEmpty) {
    b.writeln();
    b.writeln('## Not measured');
    b.writeln();
    for (final s in r.skipped) {
      b.writeln('- ${s.name}: ${s.reason}');
    }
  }
  return b.toString();
}
