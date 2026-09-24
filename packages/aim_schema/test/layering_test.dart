import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('the validation engine does not depend on aim_core', () {
    // Only the two integration files may reach into the framework. Keeping
    // the engine free of it is what would let it move out of this package
    // later, and is what lets it compile on every one of aim's runtimes,
    // including the ones that only run wasm.
    const integration = {
      'lib/src/context.dart',
      'lib/src/middleware.dart',
      'lib/src/typed.dart',
    };

    final offenders = <String>[];
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final rel = file.path.replaceAll(r'\', '/');
      if (integration.any(rel.endsWith)) continue;
      final text = file.readAsStringSync();
      // The barrel is exempt from the aim_core check only — it legitimately
      // re-exports context.dart's extension, which is what pulls aim_core
      // in transitively. It is not exempt from dart:io or package:web: if
      // the barrel itself started importing either, that would be exactly
      // the kind of layering break this guard exists to catch, and skipping
      // the whole file would let it slip past unnoticed.
      final isBarrel = rel.endsWith('lib/aim_schema.dart');
      if (!isBarrel && text.contains('aim_core')) offenders.add(rel);
      if (text.contains('dart:io') || text.contains('package:web')) {
        offenders.add(rel);
      }
    }
    expect(offenders, isEmpty);
  });
}
