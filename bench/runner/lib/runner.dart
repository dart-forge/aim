import 'dart:async';
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
    this.arguments = const [],
  });

  final Duration duration;
  final int connections;
  final int runs;
  final Duration warmup;
  final Duration pause;

  /// The command line this run was invoked with, recorded so a results
  /// file's settings are never read without knowing exactly how it was
  /// produced.
  final List<String> arguments;

  Map<String, Object?> toJson(String oha) => {
        'durationSeconds': duration.inSeconds,
        'connections': connections,
        'runs': runs,
        'warmupSeconds': warmup.inSeconds,
        'pauseSeconds': pause.inSeconds,
        'oha': oha,
        'arguments': arguments,
      };
}

/// Starts [binary], waits for its first `200` on `/`, and returns how long
/// that took together with the still-running [Process]. The caller decides
/// whether to stop it or keep it running.
///
/// If waiting for readiness fails for any reason — including [binary]
/// exiting before it answers — the process is stopped before the error is
/// rethrown, so a failed launch never leaks a still-running process.
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
  try {
    final elapsed = await _waitOrExit(process, binary, base.resolve('/'));
    return (elapsed, process);
  } catch (_) {
    await stopServer(process);
    rethrow;
  }
}

/// Races [waitUntilReady] against [process] exiting, so a process that
/// crashes on startup is reported immediately instead of being waited out
/// to [waitUntilReady]'s own timeout.
Future<Duration> _waitOrExit(Process process, File binary, Uri url) {
  final completer = Completer<Duration>();
  waitUntilReady(url).then(
    (elapsed) {
      if (!completer.isCompleted) completer.complete(elapsed);
    },
    onError: (Object error, StackTrace stack) {
      if (!completer.isCompleted) completer.completeError(error, stack);
    },
  );
  process.exitCode.then((code) {
    if (!completer.isCompleted) {
      final stderrTail = lastStderr(process).trim();
      completer.completeError(
        StateError(
          '${p.basename(binary.path)} exited with code $code before '
          'answering'
          '${stderrTail.isEmpty ? '' : ':\n$stderrTail'}',
        ),
      );
    }
  });
  return completer.future;
}

/// Builds, verifies and measures one app. Throws [StateError] if the app
/// does not answer the scenarios identically, or if a measured run's
/// status codes are not all `200` (a mismatch or a success rate below
/// 100%) — a non-comparable app is never measured.
///
/// Startup is the median of three launches after one discarded launch; the
/// first launch of a freshly compiled binary pays a one-time
/// first-execution cost on macOS and is not what a redeploy sees. Without
/// the discarded warm-up launch, `startupMs` would record that one-time
/// cost instead of the app's own startup time.
Future<AppResult> measureApp(
  AppSpec app, {
  required BenchSettings settings,
  required int port,
  required Future<File> Function(AppSpec) build,
}) async {
  final binary = await build(app);
  final base = Uri.parse('http://127.0.0.1:$port');
  final workingDirectory = appBuildDirectory(app);

  await ensurePortFree(port);
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
        if (!allOk(run)) {
          throw StateError('${app.name} / ${scenario.id}: success rate ${run.successRate}, status codes ${run.statusCodes}');
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

/// `bench/results/<date>-<label>.json`, with [label] sanitized so it is
/// always a safe file name component.
File resultsFile(String label, DateTime now) {
  final date = now.toUtc().toIso8601String().substring(0, 10);
  final safeLabel = label.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
  return File(p.join(benchRoot().path, 'results', '$date-$safeLabel.json'));
}
