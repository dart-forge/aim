import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Runs `dart analyze` on one fixture under `test/static_fixtures/` and
/// returns the machine-format diagnostics reported for that file.
///
/// Run from the package directory so the fixture resolves this package's
/// own dependencies (aim_core, aim_schema) exactly as a real caller would.
Future<List<String>> _analyze(String fixture) async {
  // Run from the package directory (as `dart test` is invoked) so the
  // fixture resolves this package's own dependencies — aim_core,
  // aim_schema — exactly as a real caller would.
  final packageRoot = Directory.current.path;
  final fixturePath = p.join('test', 'static_fixtures', fixture);
  final result = await Process.run('dart', [
    'analyze',
    '--format=machine',
    fixturePath,
  ], workingDirectory: packageRoot);
  final output = '${result.stdout}\n${result.stderr}';
  return const LineSplitter()
      .convert(output)
      .where((l) => l.isNotEmpty)
      .toList();
}

void main() {
  test('a well-formed route analyzes with no errors', () async {
    final diagnostics = await _analyze('ok.dart');
    expect(diagnostics, isEmpty, reason: diagnostics.join('\n'));
  });

  test('returning the wrong reply type is a compile error', () async {
    final diagnostics = await _analyze('wrong_reply_type.dart');
    expect(
      diagnostics.any((l) => l.contains('ARGUMENT_TYPE_NOT_ASSIGNABLE')),
      isTrue,
      reason: diagnostics.join('\n'),
    );
  });

  test('reading an omitted location is a compile error', () async {
    final diagnostics = await _analyze('omitted_location.dart');
    expect(
      diagnostics.any(
        (l) =>
            l.contains('UNDEFINED_GETTER') ||
            l.contains('UNCHECKED_USE_OF_NULLABLE_VALUE'),
      ),
      isTrue,
      reason: diagnostics.join('\n'),
    );
  });

  test('returning c.json instead of a Reply is a compile error', () async {
    final diagnostics = await _analyze('json_instead_of_reply.dart');
    expect(
      diagnostics.any(
        (l) =>
            l.contains('RETURN_OF_INVALID_TYPE_FROM_CLOSURE') &&
            l.contains('Reply'),
      ),
      isTrue,
      reason: diagnostics.join('\n'),
    );
  });

  test('a Writer getter of the wrong type is a compile error', () async {
    final diagnostics = await _analyze('wrong_getter_type.dart');
    expect(
      diagnostics.any((l) => l.contains('RETURN_OF_INVALID_TYPE_FROM_CLOSURE')),
      isTrue,
      reason: diagnostics.join('\n'),
    );
  });
}
