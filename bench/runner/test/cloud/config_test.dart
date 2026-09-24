import 'dart:io';

import 'package:bench_runner/cloud/config.dart';
import 'package:test/test.dart';

void main() {
  test('parses every field', () {
    final c = parseCloudConfig(File('test/cloud/fixtures/config.yaml').readAsStringSync());
    expect(c.label, 'tokyo-office');
    expect(c.firebaseProject, 'my-firebase-project-id');
    expect(c.supabaseProjectRef, 'abcdefghijklmnopqrst');
    expect(c.workersNamePrefix, 'aim-bench');
  });

  test('a missing key names itself', () {
    expect(
      () => parseCloudConfig('label: x\nfirebase_project: y\n'),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('supabase_project_ref'))),
    );
  });
}
