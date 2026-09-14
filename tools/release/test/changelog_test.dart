import 'package:release/changelog.dart';
import 'package:test/test.dart';

void main() {
  group('bumpChangelog', () {
    const repoUrl = 'https://github.com/dart-forge/aim';

    test('folds ## Unreleased into the new version, keeping entries', () {
      const content = '''# Changelog

## Unreleased

- **Breaking:** first entry.
- Second entry.
- Third entry.

## 0.1.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.1.0)
''';

      final result = bumpChangelog(content, '0.2.0', repoUrl: repoUrl);

      expect(
        result,
        '''# Changelog

## 0.2.0

- **Breaking:** first entry.
- Second entry.
- Third entry.

## 0.1.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.1.0)
''',
      );
    });

    test('inserts a new block after the first # header when no Unreleased '
        'and no existing version heading', () {
      const content = '''# Changelog

## 0.1.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.1.0)
''';

      final result = bumpChangelog(content, '0.2.0', repoUrl: repoUrl);

      expect(
        result,
        '''# Changelog

## 0.2.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.2.0)

## 0.1.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.1.0)
''',
      );
    });

    test('inserts at the top when there is no header at all', () {
      const content = '''## 0.1.0

Initial release.
''';

      final result = bumpChangelog(content, '0.2.0', repoUrl: repoUrl);

      expect(
        result,
        '''## 0.2.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.2.0)

## 0.1.0

Initial release.
''',
      );
    });

    test('is unchanged when ## <version> already exists and there is no '
        'Unreleased section', () {
      const content = '''# Changelog

## 0.2.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.2.0)

## 0.1.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.1.0)
''';

      final result = bumpChangelog(content, '0.2.0', repoUrl: repoUrl);

      expect(result, content);
    });

    test('is idempotent: applying twice equals applying once', () {
      const content = '''# Changelog

## Unreleased

- Some entry.

## 0.1.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.1.0)
''';

      final once = bumpChangelog(content, '0.2.0', repoUrl: repoUrl);
      final twice = bumpChangelog(once, '0.2.0', repoUrl: repoUrl);

      expect(twice, once);
    });

    test('folds a lowercase "## unreleased " heading with a trailing space',
        () {
      const content = '''# Changelog

## unreleased 

- An entry.

## 0.1.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.1.0)
''';

      final result = bumpChangelog(content, '0.2.0', repoUrl: repoUrl);

      expect(
        result,
        '''# Changelog

## 0.2.0

- An entry.

## 0.1.0

See [Release Notes](https://github.com/dart-forge/aim/releases/tag/0.1.0)
''',
      );
    });
  });
}
