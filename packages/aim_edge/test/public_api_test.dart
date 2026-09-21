import 'dart:io';

import 'package:test/test.dart';

/// The application-author barrel exports only aim_core, [EdgeContext] and
/// [EdgeEnv]. Runtime-specific names (Cloudflare's `Bindings`/`CfProperties`,
/// or a Deno equivalent) belong in the adapter packages, never here.
void main() {
  test('lib/aim_edge.dart exports only the shared surface', () {
    final source = File('lib/aim_edge.dart').readAsStringSync();
    final exports =
        RegExp(
              r'''^export\s+['"]([^'"]+)['"](\s+show\s+([^;]+))?;''',
              multiLine: true,
            )
            .allMatches(source)
            .map((m) => (uri: m.group(1)!, show: m.group(3)?.trim()))
            .toList();

    expect(exports, hasLength(3));
    expect(exports[0], (uri: 'package:aim_core/aim_core.dart', show: null));
    expect(exports[1], (uri: 'src/edge_context.dart', show: 'EdgeContext'));
    expect(exports[2], (uri: 'src/edge_env.dart', show: 'EdgeEnv'));
  });

  test('EdgeEnv is implementable from another package', () {
    // Not `sealed`: a sealed class can only be implemented inside its own
    // library, which would stop aim_workers and aim_deno from implementing
    // it and defeat the split. The compile-time proof is those packages'
    // wasm smoke tests; this guards the declaration itself.
    final source = File('lib/src/edge_env.dart').readAsStringSync();
    expect(source, contains('abstract interface class EdgeEnv'));
    expect(source, isNot(contains('sealed class EdgeEnv')));
  });

  test('adapter.dart exposes what an adapter needs, and nothing else', () {
    final source = File('lib/adapter.dart').readAsStringSync();
    final exports =
        RegExp(
              r'''^export\s+['"]([^'"]+)['"](\s+show\s+([^;]+))?;''',
              multiLine: true,
            )
            .allMatches(source)
            .map((m) => (uri: m.group(1)!, show: m.group(3)?.trim()))
            .toList();

    expect(exports, hasLength(5));
    expect(exports[0], (uri: 'src/edge_env.dart', show: 'EdgeEnv'));
    expect(exports[1], (uri: 'src/edge_raw.dart', show: 'EdgeRaw'));
    expect(exports[2], (uri: 'src/edge_request.dart', show: 'toAimRequest'));
    expect(exports[3], (uri: 'src/edge_response.dart', show: 'toWebResponse'));
    expect(exports[4], (uri: 'src/handle_fetch.dart', show: 'handleEdgeFetch'));
  });

  test('aim_edge.dart never re-grows Cloudflare-only names', () {
    final source = File('lib/aim_edge.dart').readAsStringSync();

    // Cloudflare-specific names belong in aim_workers. If one of these
    // comes back, the split has leaked.
    expect(source, isNot(contains('Bindings')));
    expect(source, isNot(contains('CfProperties')));
    expect(source, isNot(contains('serveEdge')));
  });

  test(
    'no source file mentions the Cloudflare-only CfProperties/cf binding',
    () {
      final offenders = <String>[];
      for (final file in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final text = file.readAsStringSync();
        if (text.contains('CfProperties') ||
            text.contains("getProperty('cf'")) {
          offenders.add(file.path);
        }
      }
      expect(offenders, isEmpty);
    },
  );
}
