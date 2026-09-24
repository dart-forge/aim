import 'dart:convert';

import 'package:bench_runner/cloud/parsers.dart';
import 'package:bench_runner/cloud/results.dart';
import 'package:bench_runner/results.dart' show SkippedApp;
import 'package:test/test.dart';

void main() {
  test('CloudResults round-trips and medians are computed from cycles', () {
    final t = TargetResult.fromMeasurements(
      runtime: 'workers',
      variant: 'aim',
      region: 'nearest colo',
      cycles: [
        ColdCycle(coldMs: 300, warmMedianMs: 30),
        ColdCycle(coldMs: 500, warmMedianMs: 32),
        ColdCycle(coldMs: 400, warmMedianMs: 31),
      ],
      scenarios: [ScenarioLatency.fromSamples('plaintext', [10, 30, 20])],
      upload: const UploadSize(bytes: 1000, gzipBytes: 400),
    );
    expect(t.coldMedianMs, 400);
    expect(t.warmAfterColdMedianMs, 31);
    expect(t.scenarios.single.p50Ms, 20);
    final r = CloudResults(
      label: 'l',
      timestamp: DateTime.utc(2026, 9, 24),
      environment: {'a': 1},
      settings: {'cycles': 3},
      targets: [t],
      skipped: [const SkippedApp('supabase/native', 'mismatch')],
    );
    final back = CloudResults.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map<String, Object?>);
    expect(back.targets.single.coldMedianMs, 400);
    expect(back.targets.single.upload.gzipBytes, 400);
    expect(back.skipped.single.name, 'supabase/native');
  });
}
