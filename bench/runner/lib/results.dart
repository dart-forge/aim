import 'package:bench_runner/oha.dart';
import 'package:bench_runner/stats.dart';

class ScenarioResult {
  ScenarioResult({
    required this.scenarioId,
    required this.runs,
    required this.medianRps,
    required this.medianP50Ms,
    required this.medianP99Ms,
  });

  factory ScenarioResult.fromRuns(String scenarioId, List<OhaResult> runs) {
    return ScenarioResult(
      scenarioId: scenarioId,
      runs: runs,
      medianRps: median([for (final r in runs) r.requestsPerSec]),
      medianP50Ms: median([for (final r in runs) r.p50Ms]),
      medianP99Ms: median([for (final r in runs) r.p99Ms]),
    );
  }

  final String scenarioId;
  final List<OhaResult> runs;
  final double medianRps;
  final double medianP50Ms;
  final double medianP99Ms;

  Map<String, Object?> toJson() => {
    'scenarioId': scenarioId,
    'median': {'rps': medianRps, 'p50Ms': medianP50Ms, 'p99Ms': medianP99Ms},
    'runs': [for (final r in runs) r.toJson()],
  };

  factory ScenarioResult.fromJson(Map<String, Object?> json) {
    final runs = [
      for (final r in json['runs'] as List)
        OhaResult.fromJson((r as Map).cast<String, Object?>()),
    ];
    return ScenarioResult.fromRuns(json['scenarioId'] as String, runs);
  }
}

class AppResult {
  AppResult({
    required this.name,
    required this.versions,
    required this.binaryBytes,
    required this.startupMs,
    required this.memoryKb,
    required this.scenarios,
  });

  final String name;
  final Map<String, String> versions;
  final int binaryBytes;
  final int startupMs;
  final int? memoryKb;
  final List<ScenarioResult> scenarios;

  Map<String, Object?> toJson() => {
    'name': name,
    'versions': versions,
    'binaryBytes': binaryBytes,
    'startupMs': startupMs,
    'memoryKb': memoryKb,
    'scenarios': [for (final s in scenarios) s.toJson()],
  };

  factory AppResult.fromJson(Map<String, Object?> json) => AppResult(
    name: json['name'] as String,
    versions: (json['versions'] as Map).cast<String, String>(),
    binaryBytes: json['binaryBytes'] as int,
    startupMs: json['startupMs'] as int,
    memoryKb: json['memoryKb'] as int?,
    scenarios: [
      for (final s in json['scenarios'] as List)
        ScenarioResult.fromJson((s as Map).cast<String, Object?>()),
    ],
  );
}

/// An app that was built but excluded from the results because it did not
/// answer every scenario identically, or its success rate dropped under
/// load.
class SkippedApp {
  const SkippedApp(this.name, this.reason);

  final String name;
  final String reason;

  Map<String, Object?> toJson() => {'name': name, 'reason': reason};

  factory SkippedApp.fromJson(Map<String, Object?> json) =>
      SkippedApp(json['name'] as String, json['reason'] as String);
}

class BenchResults {
  BenchResults({
    required this.label,
    required this.timestamp,
    required this.environment,
    required this.settings,
    required this.apps,
    this.skipped = const [],
  });

  final String label;
  final DateTime timestamp;
  final Map<String, Object?> environment;
  final Map<String, Object?> settings;
  final List<AppResult> apps;
  final List<SkippedApp> skipped;

  Map<String, Object?> toJson() => {
    'label': label,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'environment': environment,
    'settings': settings,
    'apps': [for (final a in apps) a.toJson()],
    'skipped': [for (final s in skipped) s.toJson()],
  };

  factory BenchResults.fromJson(Map<String, Object?> json) => BenchResults(
    label: json['label'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    environment: (json['environment'] as Map).cast<String, Object?>(),
    settings: (json['settings'] as Map).cast<String, Object?>(),
    apps: [
      for (final a in json['apps'] as List)
        AppResult.fromJson((a as Map).cast<String, Object?>()),
    ],
    skipped: [
      for (final s in (json['skipped'] as List?) ?? const [])
        SkippedApp.fromJson((s as Map).cast<String, Object?>()),
    ],
  );
}
