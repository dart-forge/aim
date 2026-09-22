import 'dart:io';

import 'package:test/test.dart';

/// The public barrel exports the shared surface (via `aim_edge`) plus the
/// Deno-only names this package adds.
void main() {
  test('lib/aim_deno.dart exports the Deno surface', () {
    final source = File('lib/aim_deno.dart').readAsStringSync();
    final exports =
        RegExp(
              r'''^export\s+['"]([^'"]+)['"](\s+show\s+([^;]+))?;''',
              multiLine: true,
            )
            .allMatches(source)
            .map((m) => (uri: m.group(1)!, show: m.group(3)?.trim()))
            .toList();

    expect(exports, hasLength(3));
    expect(exports[0], (uri: 'package:aim_edge/aim_edge.dart', show: null));
    expect(exports[1], (uri: 'src/deno_env.dart', show: 'DenoEnv'));
    expect(exports[2], (uri: 'src/serve_deno.dart', show: 'AimDeno'));
  });

  test('serveDeno is the fetch-registering entry point', () {
    final source = File('lib/src/serve_deno.dart').readAsStringSync();
    expect(source, contains('void serveDeno('));
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
