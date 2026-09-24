import 'package:bench_runner/cloud/parsers.dart';
import 'package:bench_runner/results.dart' show SkippedApp;
import 'package:bench_runner/stats.dart';

class ColdCycle {
  const ColdCycle({required this.coldMs, required this.warmMedianMs});
  final double coldMs;
  final double warmMedianMs;
  Map<String, Object?> toJson() => {'coldMs': coldMs, 'warmMedianMs': warmMedianMs};
  factory ColdCycle.fromJson(Map<String, Object?> j) =>
      ColdCycle(coldMs: (j['coldMs'] as num).toDouble(), warmMedianMs: (j['warmMedianMs'] as num).toDouble());
}

class ScenarioLatency {
  ScenarioLatency({required this.scenarioId, required this.samplesMs})
      : p50Ms = percentile(samplesMs, 50),
        p99Ms = percentile(samplesMs, 99),
        minMs = percentile(samplesMs, 0);
  factory ScenarioLatency.fromSamples(String id, List<double> samplesMs) =>
      ScenarioLatency(scenarioId: id, samplesMs: samplesMs);
  final String scenarioId;
  final List<double> samplesMs;
  final double p50Ms, p99Ms, minMs;
  Map<String, Object?> toJson() =>
      {'scenarioId': scenarioId, 'p50Ms': p50Ms, 'p99Ms': p99Ms, 'minMs': minMs, 'samplesMs': samplesMs};
  factory ScenarioLatency.fromJson(Map<String, Object?> j) => ScenarioLatency.fromSamples(
    j['scenarioId'] as String,
    [for (final s in j['samplesMs'] as List) (s as num).toDouble()],
  );
}

class TargetResult {
  TargetResult._({
    required this.runtime,
    required this.variant,
    required this.region,
    required this.cycles,
    required this.scenarios,
    required this.upload,
  }) : coldMedianMs = median([for (final c in cycles) c.coldMs]),
       warmAfterColdMedianMs = median([for (final c in cycles) c.warmMedianMs]);

  factory TargetResult.fromMeasurements({
    required String runtime,
    required String variant,
    required String region,
    required List<ColdCycle> cycles,
    required List<ScenarioLatency> scenarios,
    required UploadSize upload,
  }) => TargetResult._(
    runtime: runtime,
    variant: variant,
    region: region,
    cycles: cycles,
    scenarios: scenarios,
    upload: upload,
  );

  final String runtime, variant, region;
  final List<ColdCycle> cycles;
  final double coldMedianMs, warmAfterColdMedianMs;
  final List<ScenarioLatency> scenarios;
  final UploadSize upload;

  Map<String, Object?> toJson() => {
    'runtime': runtime,
    'variant': variant,
    'region': region,
    'cold': {
      'medianMs': coldMedianMs,
      'warmAfterColdMedianMs': warmAfterColdMedianMs,
      'cycles': [for (final c in cycles) c.toJson()],
    },
    'scenarios': [for (final s in scenarios) s.toJson()],
    'upload': upload.toJson(),
  };

  factory TargetResult.fromJson(Map<String, Object?> j) {
    final cold = j['cold'] as Map;
    return TargetResult.fromMeasurements(
      runtime: j['runtime'] as String,
      variant: j['variant'] as String,
      region: j['region'] as String,
      cycles: [for (final c in cold['cycles'] as List) ColdCycle.fromJson((c as Map).cast())],
      scenarios: [for (final s in j['scenarios'] as List) ScenarioLatency.fromJson((s as Map).cast())],
      upload: UploadSize.fromJson((j['upload'] as Map).cast()),
    );
  }
}

/// Same shape as stage 1's `BenchResults`, but with cloud `TargetResult`s
/// instead of local `AppResult`s.
class CloudResults {
  CloudResults({
    required this.label,
    required this.timestamp,
    required this.environment,
    required this.settings,
    required this.targets,
    this.skipped = const [],
  });

  final String label;
  final DateTime timestamp;
  final Map<String, Object?> environment;
  final Map<String, Object?> settings;
  final List<TargetResult> targets;
  final List<SkippedApp> skipped;

  Map<String, Object?> toJson() => {
    'label': label,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'environment': environment,
    'settings': settings,
    'targets': [for (final t in targets) t.toJson()],
    'skipped': [for (final s in skipped) s.toJson()],
  };

  factory CloudResults.fromJson(Map<String, Object?> json) => CloudResults(
    label: json['label'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    environment: (json['environment'] as Map).cast<String, Object?>(),
    settings: (json['settings'] as Map).cast<String, Object?>(),
    targets: [for (final t in json['targets'] as List) TargetResult.fromJson((t as Map).cast<String, Object?>())],
    skipped: [
      for (final s in (json['skipped'] as List?) ?? const [])
        SkippedApp.fromJson((s as Map).cast<String, Object?>()),
    ],
  );
}
