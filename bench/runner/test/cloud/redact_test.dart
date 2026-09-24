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
      containsAll(['supabase.co', 'supabase project ref']),
    );
  });

  test('finds the firebase project id and workers name prefix even without a URL', () {
    expect(
      leakedIdentifiers('{"note":"my-firebase-project-id"}', config),
      ['firebase project id'],
    );
    expect(
      leakedIdentifiers('{"note":"aim-bench-aim"}', config),
      ['workers name prefix'],
    );
  });

  test('a clean JSON leaks nothing', () {
    expect(
      leakedIdentifiers('{"runtime":"workers","variant":"aim","region":"nearest colo"}', config),
      isEmpty,
    );
  });

  test('the returned labels never contain the raw config value', () {
    final json = '{"note":"${config.firebaseProject} ${config.supabaseProjectRef} '
        '${config.workersNamePrefix}"}';
    final found = leakedIdentifiers(json, config);
    expect(found, isNotEmpty);
    for (final label in found) {
      expect(label, isNot(contains(config.firebaseProject)));
      expect(label, isNot(contains(config.supabaseProjectRef)));
      expect(label, isNot(contains(config.workersNamePrefix)));
    }
  });
}
