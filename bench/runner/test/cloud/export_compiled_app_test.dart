import 'package:bench_runner/cloud/export_compiled_app.dart';
import 'package:test/test.dart';

void main() {
  test('adds export to the CompiledApp class', () {
    final out = exportCompiledApp('class CompiledApp {\n');
    expect(out, startsWith('export class CompiledApp'));
  });

  test('leaves text without the class unchanged', () {
    const src = 'const x = 1;\n';
    expect(exportCompiledApp(src), src);
  });
}
