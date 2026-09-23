import 'dart:io';

import 'package:aim_cli/src/version.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('aimCliVersion', () {
    test('matches the version: field in pubspec.yaml', () {
      // dart test runs with the package directory as the working
      // directory, so pubspec.yaml is resolved relative to it.
      final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync())
          as YamlMap;

      expect(aimCliVersion, equals(pubspec['version']));
    });
  });

  group('aim --version', () {
    test('prints "aim_cli <version>" and exits 0', () async {
      final result = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'bin/aim.dart', '--version'],
        workingDirectory: Directory.current.path,
      );

      expect(result.exitCode, equals(0));
      expect(
        (result.stdout as String).trim(),
        equals('aim_cli $aimCliVersion'),
      );
    });
  });
}
