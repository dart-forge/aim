import 'package:release/workspace.dart';
import 'package:test/test.dart';

void main() {
  group('workspaceMembers', () {
    test('returns members listed under workspace: in order', () {
      const pubspec = '''
name: _
publish_to: none
environment:
  sdk: ^3.13.0
workspace:
  - packages/aim_core
  - packages/aim_server
  - tools/release
''';

      final result = workspaceMembers(pubspec);

      expect(result, [
        'packages/aim_core',
        'packages/aim_server',
        'tools/release',
      ]);
    });

    test('returns an empty list when there is no workspace: list', () {
      const pubspec = '''
name: some_package
version: 1.0.0
environment:
  sdk: ^3.13.0
''';

      expect(workspaceMembers(pubspec), isEmpty);
    });

    test('returns an empty list for an empty workspace: list', () {
      const pubspec = '''
name: _
workspace: []
''';

      expect(workspaceMembers(pubspec), isEmpty);
    });
  });
}
