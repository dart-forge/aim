import 'dart:io';

import 'package:bench_runner/cloud/config.dart';
import 'package:bench_runner/cloud/probe.dart';
import 'package:bench_runner/cloud/results.dart';
import 'package:bench_runner/cloud/targets.dart';
import 'package:bench_runner/cloud/urls.dart';
import 'package:bench_runner/process.dart';
import 'package:bench_runner/scenarios.dart';
import 'package:bench_runner/stats.dart';
import 'package:bench_runner/verify.dart';
import 'package:path/path.dart' as p;

/// How many deploy-and-measure cycles to run, how many warm samples to take
/// right after each cycle's cold one, how many sequential requests each
/// scenario is measured with afterwards, and how long to pause between
/// targets.
class CloudSettings {
  const CloudSettings({
    this.cycles = 5,
    this.warmAfterCold = 20,
    this.requests = 100,
    this.pauseBetweenTargets = const Duration(seconds: 5),
    this.arguments = const [],
  });

  final int cycles;
  final int warmAfterCold;
  final int requests;
  final Duration pauseBetweenTargets;

  /// The command line this run was invoked with, recorded so a results
  /// file's settings are never read without knowing exactly how it was
  /// produced.
  final List<String> arguments;

  Map<String, Object?> toJson() => {
    'cycles': cycles,
    'warmAfterCold': warmAfterCold,
    'requests': requests,
    'pauseBetweenTargetsSeconds': pauseBetweenTargets.inSeconds,
    'arguments': arguments,
  };
}

double _ms(Duration d) => d.inMicroseconds / 1000;

/// Builds, deploys and measures [target] [CloudSettings.cycles] times, then
/// measures every shared scenario once against the last deployment.
///
/// Cycle 1's order is cold → verify → warm: right after that deploy, a
/// fresh-connection request is timed as the cold sample, then the shared
/// scenarios are checked against the deployment ([verifyApp]; a mismatch
/// throws [StateError] and no more of this target is measured), and only
/// then are the [CloudSettings.warmAfterCold] warm samples taken on a
/// kept-alive connection. Cycles 2..[CloudSettings.cycles] skip verify
/// (already known-good from cycle 1) and go cold → warm.
///
/// After the last cycle, each of [scenarios] is measured with
/// [CloudSettings.requests] sequential requests on a single kept-alive
/// connection, giving the warm p50/p99/min this target answers with.
///
/// The target's upload size is measured last, from [CloudTarget.size]. A
/// measured size of zero (for example a Functions AOT bundle directory
/// that build output did not land in) is recorded as-is with a warning
/// logged through [log]; it does not fail the run — that is left to
/// whoever reads the results.
Future<TargetResult> measureTarget(
  CloudTarget target,
  CloudConfig config,
  CloudSettings settings, {
  required void Function(String) log,
}) async {
  final dir = Directory(p.join(cloudRoot().path, target.directory));
  for (final step in target.build(config)) {
    await runStep(step, workingDirectory: dir);
  }

  Uri? base;
  var lastDeploy = '';
  final cycles = <ColdCycle>[];
  for (var i = 1; i <= settings.cycles; i++) {
    log('${target.name}: deploy $i/${settings.cycles}');
    lastDeploy = await runCapturing(target.deploy(config), workingDirectory: dir);
    base = target.url(config, lastDeploy) ??
        (throw StateError('${target.name}: could not find the deployed URL in the deploy output'));

    // Cold sample: a fresh client, so this includes a new TCP + TLS
    // handshake, exactly what a genuinely cold request pays. Right after a
    // brand-new deployment, the platform's edge may 404 for a while as the
    // route propagates; coldProbe retries past that instead of counting it
    // as the app's own answer.
    final cold = await coldProbe(joinPath(base, '/'));

    if (i == 1) {
      final mismatches = await verifyApp(base);
      if (mismatches.isNotEmpty) {
        throw StateError('${target.name} is not comparable:\n  ${mismatches.join('\n  ')}');
      }
    }

    final client = HttpClient();
    List<Duration> warm;
    try {
      warm = await sequentialLatencies(joinPath(base, '/'), settings.warmAfterCold, client: client);
    } finally {
      client.close(force: true);
    }
    cycles.add(
      ColdCycle(
        coldMs: _ms(cold.ttfb),
        warmMedianMs: median([for (final d in warm) _ms(d)]),
        notFoundRetries: cold.notFoundRetries,
      ),
    );
    log(
      '${target.name}: cold ${cycles.last.coldMs.toStringAsFixed(0)} ms, '
      'warm median ${cycles.last.warmMedianMs.toStringAsFixed(0)} ms'
      '${cold.notFoundRetries > 0 ? ', ${cold.notFoundRetries} 404 retries before first answer' : ''}',
    );
  }

  final client = HttpClient();
  final latencies = <ScenarioLatency>[];
  try {
    for (final scenario in scenarios) {
      final samples = await sequentialLatencies(
        joinPath(base!, scenario.path),
        settings.requests,
        method: scenario.method,
        jsonBody: scenario.requestBody,
        client: client,
      );
      latencies.add(ScenarioLatency.fromSamples(scenario.id, [for (final d in samples) _ms(d)]));
      log(
        '${target.name} / ${scenario.id}: '
        'p50 ${latencies.last.p50Ms.toStringAsFixed(0)} ms  '
        'p99 ${latencies.last.p99Ms.toStringAsFixed(0)} ms',
      );
    }
  } finally {
    client.close(force: true);
  }

  final upload = await target.size(dir, lastDeploy);
  if (upload.bytes == 0) {
    log('${target.name}: warning, measured upload size is 0 bytes');
  }

  return TargetResult.fromMeasurements(
    runtime: target.runtime.name,
    variant: target.variant.name,
    region: target.region,
    cycles: cycles,
    scenarios: latencies,
    upload: upload,
  );
}
