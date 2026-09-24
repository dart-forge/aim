import 'dart:io';

import 'package:bench_runner/cloud/parsers.dart';
import 'package:test/test.dart';

void main() {
  final wrangler = File('test/cloud/fixtures/wrangler-deploy.txt').readAsStringSync();
  final firebase = File('test/cloud/fixtures/firebase-deploy.txt').readAsStringSync();

  test('wrangler upload size in bytes, with gzip', () {
    final s = parseWranglerUpload(wrangler)!;
    expect(s.bytes, (168.06 * 1024).round());
    expect(s.gzipBytes, (48.41 * 1024).round());
  });
  test('wrangler url', () {
    expect(parseWranglerUrl(wrangler).toString(), 'https://aim-bench-aim.example-account.workers.dev');
  });
  test('firebase function url by name', () {
    expect(parseFirebaseFunctionUrl(firebase, 'benchAim').toString(), 'https://benchaim-abc123xyz-uc.a.run.app');
    expect(parseFirebaseFunctionUrl(firebase, 'other'), isNull);
  });
  test('sizeOfFiles sums bytes and gzips', () async {
    final dir = await Directory.systemTemp.createTemp('bench-size');
    addTearDown(() => dir.delete(recursive: true));
    final f = File('${dir.path}/a.txt')..writeAsStringSync('a' * 10000);
    final s = await sizeOfFiles([f]);
    expect(s.bytes, 10000);
    expect(s.gzipBytes, lessThan(1000));
  });
}
