import 'dart:io';

import 'package:test/test.dart';

/// The public barrel may export aim_core, [ShelfRequest] and
/// [ShelfRequestAccess] (the typed `raw` accessor and the alias that makes
/// its return type nameable — see `functions_request.dart`), and
/// [AimFunctions] (the entry point) only. Mirrors
/// `aim_edge/test/public_api_test.dart`: the point is that the exported
/// surface cannot widen — a new export, or a new member on either exported
/// extension — without this test failing.
void main() {
  test('lib/aim_functions.dart exports only the allowed surface', () {
    final source = File('lib/aim_functions.dart').readAsStringSync();
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
    expect(exports[1], (
      uri: 'src/functions_request.dart',
      show: 'ShelfRequest, ShelfRequestAccess',
    ));
    expect(exports[2], (uri: 'src/serve_functions.dart', show: 'AimFunctions'));
  });

  test('ShelfRequestAccess exposes only shelfRequest', () {
    final body = _extensionBody(
      File('lib/src/functions_request.dart').readAsStringSync(),
      'ShelfRequestAccess',
    );
    final members = _topLevelDeclarationLines(body);

    expect(members, hasLength(1));
    expect(members.single, contains('ShelfRequest? get shelfRequest'));
  });

  test('AimFunctions exposes only serveFunction', () {
    final body = _extensionBody(
      File('lib/src/serve_functions.dart').readAsStringSync(),
      'AimFunctions',
    );
    final members = _topLevelDeclarationLines(body);

    expect(members, hasLength(1));
    expect(
      members.single,
      contains(
        'Future<shelf.Response> Function(shelf.Request) serveFunction()',
      ),
    );
  });
}

/// Every two-space-indented line that looks like the start of a member
/// declaration: starts with a letter, so doc comments (which start with
/// `/`) are excluded automatically. If a new member is added to the
/// extension, it adds a line here and the length assertions above catch it.
List<String> _topLevelDeclarationLines(String extensionBody) => RegExp(
  r'^  [A-Za-z_][^\n]*$',
  multiLine: true,
).allMatches(extensionBody).map((m) => m.group(0)!).toList();

String _extensionBody(String source, String name) {
  final start = source.indexOf(RegExp('extension $name\\b'));
  expect(start, greaterThanOrEqualTo(0), reason: 'extension $name not found');
  var depth = 0;
  for (var i = source.indexOf('{', start); i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') depth--;
    if (depth == 0) return source.substring(start, i + 1);
  }
  fail('unbalanced braces in $name');
}
