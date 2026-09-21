import 'dart:io';

import 'package:test/test.dart';

/// The public barrel exports the shared surface (via `aim_edge`) plus the
/// Cloudflare-only names this package adds. `serveEdge` — `aim_edge`'s
/// pre-split entry point — must never come back here as anything but
/// `serveWorkers`.
void main() {
  test('lib/aim_workers.dart exports the workerd surface', () {
    final source = File('lib/aim_workers.dart').readAsStringSync();
    final exports =
        RegExp(
              r'''^export\s+['"]([^'"]+)['"](\s+show\s+([^;]+))?;''',
              multiLine: true,
            )
            .allMatches(source)
            .map((m) => (uri: m.group(1)!, show: m.group(3)?.trim()))
            .toList();

    expect(exports, hasLength(5));
    expect(exports[0], (uri: 'package:aim_edge/aim_edge.dart', show: null));
    expect(exports[1], (uri: 'src/cf_properties.dart', show: 'CfProperties'));
    expect(exports[2], (uri: 'src/serve_workers.dart', show: 'AimWorkers'));
    expect(exports[3], (
      uri: 'src/workers_context.dart',
      show: 'WorkersContext',
    ));
    expect(exports[4], (uri: 'src/workers_env.dart', show: 'WorkersEnv'));
  });

  test('serveWorkers is the fetch-registering entry point', () {
    final source = File('lib/src/serve_workers.dart').readAsStringSync();
    expect(source, contains('void serveWorkers()'));
  });

  test('no source file mentions serveEdge', () {
    final offenders = <String>[];
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      if (file.readAsStringSync().contains('serveEdge')) {
        offenders.add(file.path);
      }
    }
    expect(offenders, isEmpty, reason: 'serveEdge leaked into: $offenders');
  });
}
