import 'dart:io';

import 'package:bench_runner/apps.dart';
import 'package:bench_runner/environment.dart';
import 'package:bench_runner/oha.dart';
import 'package:bench_runner/process.dart';
import 'package:bench_runner/results.dart';
import 'package:bench_runner/scenarios.dart';
import 'package:bench_runner/stats.dart';
import 'package:bench_runner/verify.dart';
import 'package:path/path.dart' as p;

class BenchSettings {
  const BenchSettings({
    this.duration = const Duration(seconds: 10),
    this.connections = 64,
    this.runs = 5,
    this.warmup = const Duration(seconds: 3),
    this.pause = const Duration(seconds: 2),
  });

  final Duration duration;
  final int connections;
  final int runs;
  final Duration warmup;
  final Duration pause;

  Map<String, Object?> toJson(String oha) => {
        'durationSeconds': duration.inSeconds,
        'connections': connections,
        'runs': runs,
        'warmupSeconds': warmup.inSeconds,
        'pauseSeconds': pause.inSeconds,
        'oha': oha,
      };
}

/// Starts [binary], waits for its first `200` on `/`, and returns how long
/// that took together with the still-running [Process]. The caller decides
/// whether to stop it or keep it running.
Future<(Duration, Process)> _launchAndTime(
  File binary, {
  required int port,
  required Directory workingDirectory,
  required Uri base,
}) async {
  final process = await startServer(
    binary,
    port: port,
    workingDirectory: workingDirectory,
  );
  final elapsed = await waitUntilReady(base.resolve('/'));
  return (elapsed, process);
}

/// Builds, verifies and measures one app. Throws [StateError] if the app
/// does not answer the scenarios identically — a non-comparable app is
/// never measured.
///
/// Startup is the median of three launches, each measured after one
/// discarded warm-up launch. The first launch of a freshly compiled binary
/// pays macOS's one-time code-signing/first-execution check (measured
/// 510–900 ms on this machine), while every later launch of the same
/// binary takes 52–59 ms; without the warm-up launch, `startupMs` would
/// record that one-time OS check instead of the app's own startup cost.
Future<AppResult> measureApp(
  AppSpec app, {
  required BenchSettings settings,
  required int port,
  required Future<File> Function(AppSpec) build,
}) async {
  final binary = await build(app);
  final base = Uri.parse('http://127.0.0.1:$port');
  final workingDirectory = appBuildDirectory(app);

  final warmup = await _launchAndTime(
    binary,
    port: port,
    workingDirectory: workingDirectory,
    base: base,
  );
  await stopServer(warmup.$2);

  final startupSamples = <double>[];
  late Process process;
  for (var i = 0; i < 3; i++) {
    final (elapsed, launched) = await _launchAndTime(
      binary,
      port: port,
      workingDirectory: workingDirectory,
      base: base,
    );
    startupSamples.add(elapsed.inMilliseconds.toDouble());
    if (i < 2) {
      await stopServer(launched);
    } else {
      // The last of the three measured launches is kept running for verify
      // and the load runs below, instead of paying a fifth launch for it.
      process = launched;
    }
  }
  final startupMs = median(startupSamples).round();

  try {
    final mismatches = await verifyApp(base);
    if (mismatches.isNotEmpty) {
      throw StateError('${app.name} is not comparable:\n  ${mismatches.join('\n  ')}');
    }

    final results = <ScenarioResult>[];
    for (final scenario in scenarios) {
      stdout.writeln('   ${app.name} / ${scenario.id}: warmup');
      await runOha(scenario, base, duration: settings.warmup, connections: settings.connections);
      final runs = <OhaResult>[];
      for (var i = 1; i <= settings.runs; i++) {
        await Future<void>.delayed(settings.pause);
        final run = await runOha(scenario, base, duration: settings.duration, connections: settings.connections);
        if (run.successRate < 1) {
          throw StateError('${app.name} / ${scenario.id}: success rate ${run.successRate} (${run.statusCodes})');
        }
        stdout.writeln('   ${app.name} / ${scenario.id}: run $i  ${run.requestsPerSec.round()} req/s  p50 ${run.p50Ms.toStringAsFixed(2)} ms  p99 ${run.p99Ms.toStringAsFixed(2)} ms');
        runs.add(run);
      }
      results.add(ScenarioResult.fromRuns(scenario.id, runs));
    }

    final memory = await memoryFootprintKb(process.pid);
    final lock = File(p.join(appDirectory(app).path, 'pubspec.lock'));
    final versions = lock.existsSync()
        ? lockedVersions(lock.readAsStringSync(), app.lockPackages)
        : <String, String>{};
    return AppResult(
      name: app.name,
      versions: versions,
      binaryBytes: binary.lengthSync(),
      startupMs: startupMs,
      memoryKb: memory,
      scenarios: results,
    );
  } finally {
    await stopServer(process);
  }
}

/// `bench/results/<date>-<label>.json`
File resultsFile(String label, DateTime now) {
  final date = now.toUtc().toIso8601String().substring(0, 10);
  return File(p.join(benchRoot().path, 'results', '$date-$label.json'));
}
