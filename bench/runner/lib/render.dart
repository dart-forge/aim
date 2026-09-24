import 'package:bench_runner/results.dart';
import 'package:bench_runner/scenarios.dart';

/// Markdown for docs: environment, one table per scenario, then footprint.
/// Numbers only — the prose around them is written by hand, after reading them.
String renderMarkdown(BenchResults r) {
  final b = StringBuffer();
  final env = r.environment;
  final memoryGb = (env['memoryBytes'] as num?) == null
      ? '?'
      : ((env['memoryBytes'] as num) / (1024 * 1024 * 1024)).toStringAsFixed(0);

  b.writeln('## Environment');
  b.writeln();
  b.writeln(
    '- Date: ${r.timestamp.toUtc().toIso8601String().substring(0, 10)}',
  );
  b.writeln(
    '- Machine: ${env['cpu']}, ${env['cores']} cores, $memoryGb GiB, ${env['os']} (${env['arch']})',
  );
  b.writeln('- Dart: ${env['dart']}');
  if (env['aimCommit'] != null) {
    b.writeln('- Aim commit: ${env['aimCommit']}');
  }
  b.writeln(
    '- Load generator: ${r.settings['oha']}, ${r.settings['connections']} connections, ${r.settings['durationSeconds']} s per run, median of ${r.settings['runs']} runs',
  );
  b.writeln(
    "- Every app is a `dart compile exe` binary, one isolate, no middleware; the load generator connects to 127.0.0.1 (dart_frog's generated server listens on all interfaces, the others on loopback only).",
  );
  b.writeln(
    '- Startup is the median of three launches after one discarded launch; '
    'the first launch of a freshly compiled binary pays a one-time '
    'first-execution cost on macOS and is not what a redeploy sees.',
  );
  b.writeln();
  b.writeln('## Versions');
  b.writeln();
  b.writeln('| App | Packages |');
  b.writeln('|---|---|');
  for (final app in r.apps) {
    final versions = app.versions.isEmpty
        ? 'dart:io only'
        : app.versions.entries.map((e) => '${e.key} ${e.value}').join(', ');
    b.writeln('| ${app.name} | $versions |');
  }
  b.writeln();

  for (final scenario in scenarios) {
    b.writeln('### ${scenario.id}');
    b.writeln();
    b.writeln('`${scenario.method} ${scenario.path}`');
    b.writeln();
    b.writeln('| App | Requests/s | p50 (ms) | p99 (ms) |');
    b.writeln('|---|---:|---:|---:|');
    for (final app in r.apps) {
      final s = app.scenarios.where((s) => s.scenarioId == scenario.id);
      if (s.isEmpty) continue;
      final m = s.single;
      b.writeln(
        '| ${app.name} | ${_thousands(m.medianRps)} | ${m.medianP50Ms.toStringAsFixed(2)} | ${m.medianP99Ms.toStringAsFixed(2)} |',
      );
    }
    b.writeln();
  }

  b.writeln('### Footprint');
  b.writeln();
  b.writeln(
    '| App | Startup to first 200, warm binary (ms) | Memory after load (MiB) | Binary (MiB) |',
  );
  b.writeln('|---|---:|---:|---:|');
  for (final app in r.apps) {
    final memory = app.memoryKb == null
        ? '?'
        : (app.memoryKb! / 1024).toStringAsFixed(1);
    final bin = (app.binaryBytes / (1024 * 1024)).toStringAsFixed(1);
    b.writeln('| ${app.name} | ${app.startupMs} | $memory | $bin |');
  }

  if (r.skipped.isNotEmpty) {
    b.writeln();
    b.writeln('### Not measured');
    b.writeln();
    for (final s in r.skipped) {
      b.writeln('- ${s.name}: ${s.reason}');
    }
  }
  return b.toString();
}

String _thousands(double value) {
  final digits = value.round().toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}
