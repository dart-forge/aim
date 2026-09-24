/// Median of [values]; the average of the two middle values for even counts.
double median(List<double> values) {
  if (values.isEmpty) {
    throw ArgumentError.value(values, 'values', 'must not be empty');
  }
  final sorted = List<double>.of(values)..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Nearest-rank percentile; [p] in 0..100.
double percentile(List<double> values, double p) {
  if (values.isEmpty) throw ArgumentError.value(values, 'values', 'must not be empty');
  final sorted = List<double>.of(values)..sort();
  if (p <= 0) return sorted.first;
  final rank = (p / 100 * sorted.length).ceil().clamp(1, sorted.length);
  return sorted[rank - 1];
}
