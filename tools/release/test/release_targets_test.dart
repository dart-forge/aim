import 'package:release/release_targets.dart';
import 'package:test/test.dart';

void main() {
  group('isPublishToNone', () {
    test(
      'returns true for a top-level package pubspec with publish_to: none',
      () {
        const pubspec = '''
name: aim_sqlite
description: A native SQLite driver for Dart.
version: 0.1.0
publish_to: none
resolution: workspace

environment:
  sdk: ^3.13.0

dependencies:
  aim_database: ^0.2.0
''';

        expect(isPublishToNone(pubspec), isTrue);
      },
    );

    test(
      'returns false for a normal top-level package pubspec (bump case 1)',
      () {
        const pubspec = '''
name: aim_database
version: 0.2.0
resolution: workspace

environment:
  sdk: ^3.13.0

dependencies:
  aim_core: ^0.2.0
''';

        expect(isPublishToNone(pubspec), isFalse);
      },
    );

    test('returns false when publish_to points at a hosted pub server', () {
      const pubspec = '''
name: some_package
version: 1.0.0
publish_to: https://my-private-pub.example.com
''';

      expect(isPublishToNone(pubspec), isFalse);
    });

    test('returns false when the pubspec has no publish_to key at all', () {
      const pubspec = '''
name: some_package
version: 1.0.0
''';

      expect(isPublishToNone(pubspec), isFalse);
    });
  });

  group('skippedDependencyViolations', () {
    test(
      'flags a published package that depends on a skipped one, naming both',
      () {
        final violations = skippedDependencyViolations(
          dependenciesByPackage: {
            'aim_postgres': ['aim_database'],
          },
          skippedPackages: {'aim_database'},
        );

        expect(violations, [
          (dependent: 'aim_postgres', dependency: 'aim_database'),
        ]);
      },
    );

    test('returns nothing when no package is skipped', () {
      final violations = skippedDependencyViolations(
        dependenciesByPackage: {
          'aim_postgres': ['aim_database'],
          'aim_database': ['aim_core'],
          'aim_core': [],
        },
        skippedPackages: {},
      );

      expect(violations, isEmpty);
    });

    test('does not flag a skipped package for depending on another skipped package', () {
      final violations = skippedDependencyViolations(
        dependenciesByPackage: {
          'aim_sqlite': ['aim_database'],
          'aim_database': [],
        },
        skippedPackages: {'aim_sqlite', 'aim_database'},
      );

      expect(violations, isEmpty);
    });

    test('reports every violating pair, not just the first', () {
      final violations = skippedDependencyViolations(
        dependenciesByPackage: {
          'aim_postgres': ['aim_database'],
          'aim_orm_postgres': ['aim_database', 'aim_orm'],
          'aim_orm': [],
        },
        skippedPackages: {'aim_database'},
      );

      expect(violations, [
        (dependent: 'aim_postgres', dependency: 'aim_database'),
        (dependent: 'aim_orm_postgres', dependency: 'aim_database'),
      ]);
    });
  });
}
