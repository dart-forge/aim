// Compiled with `dart compile wasm` by wasm_smoke_test.dart.
import 'package:aim_schema/aim_schema.dart';

/// Proves that the validation engine — pure Dart, with no `dart:io` or
/// `package:web` — compiles to WebAssembly. Since it is pure computation,
/// this plus the layering guard (see layering_test.dart) is what stands in
/// for running it on every one of aim's runtimes, including the two that
/// only run wasm.
void main() {
  final schema = Schema(
    (r) =>
        (name: r.string('name', maxLength: 80), age: r.integer('age', min: 0)),
  );
  final body = schema.parse({'name': 'naoki', 'age': 34});
  print('${body.name} ${body.age}');
}
