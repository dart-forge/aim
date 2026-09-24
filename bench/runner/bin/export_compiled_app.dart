import 'dart:io';

import 'package:bench_runner/cloud/export_compiled_app.dart';

/// Patches the `.mjs` glue that `dart compile wasm` emits for a target that
/// imports `CompiledApp` as an ES module export (Workers, Supabase).
void main(List<String> args) {
  final file = File(args.single);
  final src = file.readAsStringSync();
  file.writeAsStringSync(exportCompiledApp(src));
}
