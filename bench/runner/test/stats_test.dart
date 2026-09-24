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

  test('percentile 50 of 1..100 is 50 and 99 is 99', () {
    final v = [for (var i = 1; i <= 100; i++) i.toDouble()];
    expect(percentile(v, 50), 50);
    expect(percentile(v, 99), 99);
    expect(percentile(v, 100), 100);
    expect(percentile(v, 0), 1);
  });
}
