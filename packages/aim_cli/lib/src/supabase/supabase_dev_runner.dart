import 'dart:async';
import 'dart:io';

import 'package:aim_cli/src/edge/wasm_builder.dart';
import 'package:aim_cli/src/hot_reload/file_watcher.dart';
import 'package:aim_cli/src/utils/process_tree.dart';

/// Development loop for `aim.target: supabase`.
///
/// Compiles the entry to wasm into `<outputDir>` (normally
/// `supabase/functions/<functionName>`) and starts
/// `supabase functions serve <functionName> --no-verify-jwt`, then
/// recompiles on file changes.
///
/// Unlike the wrangler-based runner for `target: workers`, the serve process
/// here is never restarted after a rebuild: against a running Supabase
/// stack, `supabase functions serve` was confirmed to pick up a rebuilt
/// `main.wasm` on its own.
///
/// This also never runs `supabase start`. That command brings up Postgres,
/// auth and the rest of the local stack, which is too slow to start on every
/// `aim dev` and would change state outside the user's project. When the
/// stack is not already running, `supabase functions serve` exits
/// immediately, and the [ProcessException] handler below only names the
/// command the user needs to run first.
class SupabaseDevRunner {
  final String entry;

  /// The function name passed to `supabase functions serve` — the name
  /// under which Supabase serves the function, and the path segment it
  /// prepends to every request.
  final String functionName;
  final String outputDir;
  final List<String> watchPaths;
  final bool watch;

  Process? _serve;
  FileWatcher? _watcher;
  bool _isBuilding = false;
  bool _buildRequested = false;
  bool _stopping = false;

  SupabaseDevRunner({
    required this.entry,
    required this.functionName,
    required this.outputDir,
    required this.watchPaths,
    this.watch = true,
  });

  Future<void> start() async {
    print('🔨 Compiling to WebAssembly...');
    await buildWasm(entry: entry, outputDir: outputDir);
    print('');

    try {
      _serve = await Process.start('supabase', [
        'functions',
        'serve',
        functionName,
        '--no-verify-jwt',
      ], mode: ProcessStartMode.inheritStdio);
    } on ProcessException catch (e) {
      throw StateError(
        'Could not start `supabase functions serve` (${e.message}). The '
        'supabase target needs the Supabase CLI 2.7.0 or later, a running '
        'Docker daemon, and the local stack already up:\n'
        '  npm install -g supabase\n'
        '  docker info\n'
        '  supabase start',
      );
    }

    if (watch) {
      _watcher = FileWatcher(
        watchPaths: watchPaths,
        onChanged: () {
          _rebuild();
        },
      );
      await _watcher!.start();
      print('👀 Watching: ${watchPaths.join(', ')}');
    }

    final exitCode = await _serve!.exitCode;
    await _watcher?.stop();
    if (_stopping) return;
    if (exitCode != 0) {
      throw StateError('supabase functions serve exited with code $exitCode');
    }
  }

  Future<void> stop() async {
    _stopping = true;
    await _watcher?.stop();
    final serve = _serve;
    if (serve != null) {
      await killProcessTree(serve.pid);
      await serve.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => -1,
      );
    }
  }

  Future<void> _rebuild() async {
    if (_isBuilding) {
      _buildRequested = true;
      return;
    }
    _isBuilding = true;
    try {
      do {
        _buildRequested = false;
        print('📝 File change detected');
        print('🔨 Recompiling to WebAssembly...');
        final stopwatch = Stopwatch()..start();
        try {
          await buildWasm(entry: entry, outputDir: outputDir);
          print(
            '✅ Recompiled (${stopwatch.elapsedMilliseconds}ms); '
            '`supabase functions serve` will pick it up',
          );
        } on WasmBuildException catch (e) {
          print('❌ $e (keeping the previous build)');
        }
        print('');
      } while (_buildRequested);
    } finally {
      _isBuilding = false;
    }
  }
}
