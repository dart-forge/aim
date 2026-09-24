import 'package:bench_runner/cloud/urls.dart';
import 'package:test/test.dart';

void main() {
  test('appends to a base without a path', () {
    expect(joinPath(Uri.parse('http://127.0.0.1:18080'), '/users/42?name=aim').toString(),
        'http://127.0.0.1:18080/users/42?name=aim');
  });
  test('keeps the base path (Supabase function prefix)', () {
    expect(joinPath(Uri.parse('https://x.supabase.co/functions/v1/aim_bench_aim'), '/users/42?name=aim').toString(),
        'https://x.supabase.co/functions/v1/aim_bench_aim/users/42?name=aim');
  });
  test('root scenario against a base path yields the base path itself', () {
    expect(joinPath(Uri.parse('https://x.supabase.co/functions/v1/f'), '/').toString(),
        'https://x.supabase.co/functions/v1/f/');
  });
  test('a trailing slash on the base is not doubled', () {
    expect(joinPath(Uri.parse('https://h/p/'), '/json').toString(), 'https://h/p/json');
  });
}
