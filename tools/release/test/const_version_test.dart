import 'package:release/const_version.dart';
import 'package:test/test.dart';

void main() {
  group('bumpConstVersion', () {
    test('rewrites a Dart-style const with a trailing semicolon', () {
      const source = "const aimCliVersion = '0.4.0';\n";

      final result = bumpConstVersion(source, 'aimCliVersion', '0.5.0');

      expect(result, equals("const aimCliVersion = '0.5.0';\n"));
    });

    test('rewrites a TypeScript-style const with no trailing semicolon', () {
      const source = "const AIM_VERSION = '0.4.0'\n";

      final result = bumpConstVersion(source, 'AIM_VERSION', '0.5.0');

      expect(result, equals("const AIM_VERSION = '0.5.0'\n"));
    });

    test('touches only the named constant, leaving others untouched', () {
      const source = '''
const SITE_URL = 'https://aim-dart.dev';
const AIM_VERSION = '0.4.0'
const OTHER = '0.4.0'
''';

      final result = bumpConstVersion(source, 'AIM_VERSION', '0.5.0');

      expect(result, contains("const SITE_URL = 'https://aim-dart.dev';"));
      expect(result, contains("const AIM_VERSION = '0.5.0'"));
      expect(result, contains("const OTHER = '0.4.0'"));
    });

    test('is idempotent when already at the target version', () {
      const source = "const AIM_VERSION = '0.5.0'\n";

      final result = bumpConstVersion(source, 'AIM_VERSION', '0.5.0');

      expect(result, equals(source));
    });

    test('returns the source unchanged when the constant is not found', () {
      const source = "const SOMETHING_ELSE = '0.4.0'\n";

      final result = bumpConstVersion(source, 'AIM_VERSION', '0.5.0');

      expect(result, equals(source));
    });

    test('rewrites a pre-release version', () {
      const source = "const AIM_VERSION = '0.4.0'\n";

      final result = bumpConstVersion(source, 'AIM_VERSION', '0.5.0-dev.1');

      expect(result, equals("const AIM_VERSION = '0.5.0-dev.1'\n"));
    });
  });
}
