import 'dart:io';

import 'package:test/test.dart';

/// Libraries that are unavailable on WebAssembly / workerd targets.
const _forbidden = ['dart:io', 'dart:ffi', 'dart:isolate', 'dart:mirrors'];

final _importPattern = RegExp(
  r'''^\s*(import|export)\s+['"](dart:[a-z_]+)['"]''',
  multiLine: true,
);

void main() {
  test('aim_deno/lib imports no platform-only dart: libraries', () {
    final libDir = Directory('lib');
    final offenders = <String>[];

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final match in _importPattern.allMatches(source)) {
        final uri = match.group(2)!;
        if (_forbidden.contains(uri)) {
          offenders.add('${entity.path}: $uri');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Forbidden imports:\n${offenders.join('\n')}',
    );
  });
}
