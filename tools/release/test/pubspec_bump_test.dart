import 'package:release/pubspec_bump.dart';
import 'package:test/test.dart';

void main() {
  group('bumpAimConstraints', () {
    test('bumps aim_* dependencies that are plain version strings', () {
      const pubspec = '''
name: simple_table_fixture
publish_to: none
resolution: workspace

environment:
  sdk: ^3.13.0

dependencies:
  aim_orm: ^0.1.1
  aim_orm_postgres: ^0.1.1
  aim_postgres: ^0.1.1
  aim_database: ^0.1.1

dev_dependencies:
  aim_orm_codegen: ^0.1.1
  build_runner: ^2.4.0
''';

      final result = bumpAimConstraints(pubspec, '0.2.0');

      expect(result, contains('aim_orm: ^0.2.0'));
      expect(result, contains('aim_orm_postgres: ^0.2.0'));
      expect(result, contains('aim_postgres: ^0.2.0'));
      expect(result, contains('aim_database: ^0.2.0'));
      expect(result, contains('aim_orm_codegen: ^0.2.0'));
      expect(result, isNot(contains('^0.1.1')));
    });

    test('leaves non-aim_* dependencies untouched', () {
      const pubspec = '''
name: simple_table_fixture
dependencies:
  aim_orm: ^0.1.1

dev_dependencies:
  aim_orm_codegen: ^0.1.1
  build_runner: ^2.4.0
''';

      final result = bumpAimConstraints(pubspec, '0.2.0');

      expect(result, contains('build_runner: ^2.4.0'));
    });

    test('leaves path: map-valued aim_* dependencies untouched', () {
      const pubspec = '''
name: basic_sample
dependencies:
  aim_server:
    path: ../../packages/aim_server
  aim_server_cors:
    path: ../../packages/aim_server_cors

dev_dependencies:
  aim_server_testing:
    path: ../../packages/aim_server_testing
  lints: ^6.0.0
''';

      final result = bumpAimConstraints(pubspec, '0.2.0');

      expect(result, contains('path: ../../packages/aim_server'));
      expect(result, contains('path: ../../packages/aim_server_cors'));
      expect(result, contains('path: ../../packages/aim_server_testing'));
      expect(result, isNot(contains('^0.2.0')));
    });

    test('does not touch version:', () {
      const pubspec = '''
name: aim_core
version: 0.1.1
dependencies:
  aim_database: ^0.1.1
''';

      final result = bumpAimConstraints(pubspec, '0.2.0');

      expect(result, contains('version: 0.1.1'));
      expect(result, contains('aim_database: ^0.2.0'));
    });

    test('is idempotent when already at the target version', () {
      const pubspec = '''
name: simple_table_fixture
dependencies:
  aim_orm: ^0.2.0
''';

      final result = bumpAimConstraints(pubspec, '0.2.0');
      final result2 = bumpAimConstraints(result, '0.2.0');

      expect(result2, equals(result));
      expect(result, contains('aim_orm: ^0.2.0'));
    });
  });
}
