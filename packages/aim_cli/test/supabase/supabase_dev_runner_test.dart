import 'package:aim_cli/src/supabase/supabase_dev_runner.dart';
import 'package:test/test.dart';

void main() {
  group('supabaseStackNeedsStart', () {
    test('is false when supabase status exits 0 (stack already up)', () {
      expect(supabaseStackNeedsStart(0), isFalse);
    });

    test('is true when supabase status exits non-zero (stack down)', () {
      expect(supabaseStackNeedsStart(1), isTrue);
    });

    test('is true for any other non-zero exit code', () {
      expect(supabaseStackNeedsStart(127), isTrue);
    });
  });
}
