import 'package:bench_runner/cloud/config.dart';
import 'package:bench_runner/cloud/redact.dart';
import 'package:test/test.dart';

void main() {
  const config = CloudConfig(
    label: 'tokyo-office',
    firebaseProject: 'my-firebase-project-id',
    supabaseProjectRef: 'abcdefghijklmnopqrst',
    workersNamePrefix: 'aim-bench',
  );

  test('finds a workers.dev URL', () {
    expect(
      leakedIdentifiers('{"url":"https://x.workers.dev"}', config),
      ['workers.dev'],
    );
  });

  test('finds a Cloud Run URL', () {
    expect(
      leakedIdentifiers('{"url":"https://bench-aim-abc123-uc.a.run.app"}', config),
      ['run.app'],
    );
  });

  test('finds a Supabase project ref inside its URL', () {
    final json = '{"url":"https://${config.supabaseProjectRef}.supabase.co/functions/v1/f"}';
    expect(
      leakedIdentifiers(json, config),
      containsAll(['supabase.co', 'abcdefghijklmnopqrst']),
    );
  });

  test('finds the firebase project id and workers name prefix even without a URL', () {
    expect(
      leakedIdentifiers('{"note":"my-firebase-project-id"}', config),
      ['my-firebase-project-id'],
    );
    expect(
      leakedIdentifiers('{"note":"aim-bench-aim"}', config),
      ['aim-bench'],
    );
  });

  test('a clean JSON leaks nothing', () {
    expect(
      leakedIdentifiers('{"runtime":"workers","variant":"aim","region":"nearest colo"}', config),
      isEmpty,
    );
  });
}
