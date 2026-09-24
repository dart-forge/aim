import 'dart:convert';
import 'dart:io';

import 'package:bench_runner/scenarios.dart';

/// The numbers kept from one oha run.
class OhaResult {
  const OhaResult({
    required this.requestsPerSec,
    required this.p50Ms,
    required this.p99Ms,
    required this.successRate,
    required this.statusCodes,
  });

  final double requestsPerSec;
  final double p50Ms;
  final double p99Ms;
  final double successRate;
  final Map<String, int> statusCodes;

  Map<String, Object?> toJson() => {
        'requestsPerSec': requestsPerSec,
        'p50Ms': p50Ms,
        'p99Ms': p99Ms,
        'successRate': successRate,
        'statusCodes': statusCodes,
      };

  factory OhaResult.fromJson(Map<String, Object?> json) => OhaResult(
        requestsPerSec: (json['requestsPerSec'] as num).toDouble(),
        p50Ms: (json['p50Ms'] as num).toDouble(),
        p99Ms: (json['p99Ms'] as num).toDouble(),
        successRate: (json['successRate'] as num).toDouble(),
        statusCodes: (json['statusCodes'] as Map).cast<String, int>(),
      );
}

/// Parses `oha -j` output.
OhaResult parseOha(String json) {
  final root = jsonDecode(json) as Map<String, Object?>;
  final metrics = root['metrics'] as Map<String, Object?>;
  final latency = metrics['latency_ms'] as Map<String, Object?>;
  final codes = (root['statusCodeDistribution'] as Map? ?? const {})
      .map((k, v) => MapEntry(k as String, (v as num).toInt()));
  return OhaResult(
    requestsPerSec: (metrics['requests_per_sec'] as num).toDouble(),
    p50Ms: (latency['p50'] as num).toDouble(),
    p99Ms: (latency['p99'] as num).toDouble(),
    successRate: (metrics['success_rate'] as num).toDouble(),
    statusCodes: codes,
  );
}

/// Command-line arguments for one scenario against [base].
List<String> ohaArguments(
  Scenario scenario,
  Uri base, {
  required Duration duration,
  required int connections,
}) {
  final args = <String>[
    '-z', '${duration.inSeconds}s',
    '-c', '$connections',
    '--no-tui',
    '--output-format', 'json',
  ];
  if (scenario.method != 'GET') args.addAll(['-m', scenario.method]);
  if (scenario.requestBody != null) {
    args.addAll([
      '-H', 'Content-Type: application/json',
      '-d', scenario.requestBody!,
    ]);
  }
  args.add(base.resolve(scenario.path).toString());
  return args;
}

/// Runs oha once and parses its JSON.
Future<OhaResult> runOha(
  Scenario scenario,
  Uri base, {
  required Duration duration,
  required int connections,
}) async {
  final args = ohaArguments(
    scenario,
    base,
    duration: duration,
    connections: connections,
  );
  final result = await Process.run('oha', args);
  if (result.exitCode != 0) {
    throw ProcessException('oha', args, result.stderr as String, result.exitCode);
  }
  return parseOha(result.stdout as String);
}

Future<String> ohaVersion() async {
  final result = await Process.run('oha', ['--version']);
  return (result.stdout as String).trim();
}
