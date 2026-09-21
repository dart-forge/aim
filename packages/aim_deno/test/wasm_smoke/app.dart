// Compiled with `dart compile wasm` by wasm_smoke_test.dart.
import 'package:aim_core/aim_core.dart';
import 'package:aim_deno/aim_deno.dart';

/// Proves that `DenoEnv implements EdgeEnv` and the `Deno.env` js_interop
/// compile to wasm, not just the shared surface (`aim_edge` has its own
/// smoke test for that).
void main() {
  final app = Aim();
  app.get('/env', (c) async => c.text('${c.env != null}'));
  app.get('/', (c) async => c.text('ok'));
  app.serveDeno(basePath: 'demo');
}
