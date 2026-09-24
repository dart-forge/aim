/// `dart compile wasm` emits `class CompiledApp` without `export`; the glue
/// imports it, so add the keyword. Same fix `aim_cli` applies in `aim build`.
String exportCompiledApp(String mjs) =>
    mjs.replaceFirst(RegExp(r'^class CompiledApp\b', multiLine: true), 'export class CompiledApp');
