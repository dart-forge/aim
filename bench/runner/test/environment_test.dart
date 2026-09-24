import 'dart:io';

import 'package:bench_runner/environment.dart';
import 'package:test/test.dart';

void main() {
  final lock = File('test/fixtures/pubspec.lock').readAsStringSync();

  test('hosted packages report their version', () {
    expect(lockedVersions(lock, ['shelf']), {'shelf': '1.4.2'});
  });

  test('path packages report version and that they came from a path', () {
    expect(lockedVersions(lock, ['aim_core']), {'aim_core': '0.4.0 (path)'});
  });

  test('missing packages are reported as absent', () {
    expect(lockedVersions(lock, ['nope']), {'nope': 'absent'});
  });

  test('captureEnvironment has the keys the report needs', () async {
    final env = await captureEnvironment();
    expect(env.keys, containsAll(['os', 'arch', 'cpu', 'cores', 'memoryBytes', 'dart']));
    expect(env['dart'], contains('Dart SDK version'));
  });
}
