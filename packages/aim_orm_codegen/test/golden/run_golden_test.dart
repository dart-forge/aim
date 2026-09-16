@Tags(['slow'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// ゴールデンテスト
///
/// 各fixtureディレクトリでbuild_runnerを実行し、生成された
/// input.g.dartをexpected.g.dartと比較します。
void main() {
  final fixturesDir = p.join(
    Directory.current.path,
    'test',
    'golden',
    'fixtures',
  );

  final fixtures = [
    'simple_table',
    'nullable_columns',
    'foreign_key',
    'multiple_fk',
    'nullable_fk',
  ];

  group('Golden tests', () {
    for (final fixture in fixtures) {
      test(fixture, () async {
        await _runGoldenTest(fixturesDir, fixture);
      }, timeout: Timeout(Duration(minutes: 3)));
    }
  });
}

Future<void> _runGoldenTest(String fixturesDir, String fixtureName) async {
  final fixtureDir = p.join(fixturesDir, fixtureName);
  final expectedPath = p.join(fixtureDir, 'expected.g.dart');
  final generatedPath = p.join(fixtureDir, 'lib', 'input.g.dart');

  // 既存の生成ファイルを削除
  final generatedFile = File(generatedPath);
  if (generatedFile.existsSync()) {
    generatedFile.deleteSync();
  }

  // build_runnerを実行
  final result = await Process.run(
    'dart',
    ['run', 'build_runner', 'build', '--delete-conflicting-outputs'],
    workingDirectory: fixtureDir,
  );

  if (result.exitCode != 0) {
    fail('build_runner failed for $fixtureName:\n'
        'stdout: ${result.stdout}\n'
        'stderr: ${result.stderr}');
  }

  // 生成されたファイルを読み込み
  final generated = File(generatedPath);
  if (!generated.existsSync()) {
    fail('Generated file not found: $generatedPath');
  }

  final expected = File(expectedPath);
  if (!expected.existsSync()) {
    fail('Expected file not found: $expectedPath');
  }

  final generatedContent = generated.readAsStringSync();
  final expectedContent = expected.readAsStringSync();

  // 正規化して比較（空白の違いを無視）
  expect(
    _normalize(generatedContent),
    equals(_normalize(expectedContent)),
    reason: 'Generated code does not match expected for $fixtureName',
  );
}

/// コードを正規化（空白、改行の違いを無視）
String _normalize(String code) {
  return code
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .join('\n');
}
