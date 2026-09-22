import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('the validation engine does not depend on aim_core', () {
    // Only the two integration files may reach into the framework. Keeping
    // the engine free of it is what would let it move out of this package
    // later, and is what lets it compile on every one of aim's runtimes,
    // including the ones that only run wasm.
    const integration = {'lib/src/context.dart', 'lib/src/middleware.dart'};

    final offenders = <String>[];
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final rel = file.path.replaceAll(r'\', '/');
      if (integration.any(rel.endsWith)) continue;
      if (rel.endsWith('lib/aim_schema.dart')) {
        continue; // the barrel re-exports
      }
      final text = file.readAsStringSync();
      if (text.contains('aim_core') ||
          text.contains('dart:io') ||
          text.contains('package:web')) {
        offenders.add(rel);
      }
    }
    expect(offenders, isEmpty);
  });
}
