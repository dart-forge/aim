import 'package:bench_runner/stats.dart';
import 'package:test/test.dart';

void main() {
  test('median of an odd-length list is the middle value', () {
    expect(median([3, 1, 2]), 2);
  });

  test('median of an even-length list averages the two middle values', () {
    expect(median([4, 1, 3, 2]), 2.5);
  });

  test('median does not reorder the caller\'s list', () {
    final values = [3.0, 1.0, 2.0];
    median(values);
    expect(values, [3.0, 1.0, 2.0]);
  });

  test('median of an empty list throws', () {
    expect(() => median([]), throwsArgumentError);
  });
}
