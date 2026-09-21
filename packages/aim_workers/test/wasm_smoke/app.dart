// Compiled with `dart compile wasm` by wasm_smoke_test.dart.
import 'package:aim_workers/aim_workers.dart';

/// Proves that `WorkersEnv implements EdgeEnv` and the rest of the workerd
/// serving path compile to wasm, not just the shared surface (`aim_edge` has
/// its own smoke test for that).
void main() {
  final app = Aim();
  app.get('/env', (c) async => c.text('${c.env != null}'));
  app.get('/cf', (c) async => c.text('${c.cf?.country}'));
  app.get('/', (c) async => c.text('ok'));
  app.serveWorkers();
}
