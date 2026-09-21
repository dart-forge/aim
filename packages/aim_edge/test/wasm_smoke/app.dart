// Compiled with `dart compile wasm` by wasm_smoke_test.dart.
import 'package:aim_edge/aim_edge.dart';

/// Compiled by wasm_smoke_test.dart. Uses the shared surface only — the
/// serving adapters have their own smoke tests.
void main() {
  final app = Aim();
  app.get('/', (c) async => c.text(c.env?.string('GREETING') ?? '(unset)'));
}
