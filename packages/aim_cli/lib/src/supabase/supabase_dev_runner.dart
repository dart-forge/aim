import 'dart:async';
import 'dart:io';

import 'package:aim_cli/src/edge/wasm_builder.dart';
import 'package:aim_cli/src/hot_reload/file_watcher.dart';
import 'package:aim_cli/src/utils/process_tree.dart';

/// Whether the local Supabase stack needs to be started, given the exit
/// code of `supabase status`.
///
/// Measured: `supabase status` exits 0 when the stack for this project is
/// already up, and 1 when it is down. The check is project-scoped (its
/// error output names containers like `supabase_db_<project>`), so this
/// only decides for the project `supabase status` was run in.
bool supabaseStackNeedsStart(int statusExitCode) => statusExitCode != 0;

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
/// Before starting `supabase functions serve`, this checks whether the
/// local stack is already running (`supabase status`, see
/// [supabaseStackNeedsStart]) and runs `supabase start` itself when it is
/// not — after the wasm build above, so `supabase start` never has to read
/// a function whose `main.mjs` does not exist yet. The stack is left
/// running when `aim dev` exits, including on Ctrl-C: [stop] only ever
/// touches the `functions serve` process, never the stack, since another
/// tool may be sharing the same local database.
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

    await _ensureStackRunning();

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
        'supabase target needs the Supabase CLI 2.7.0 or later and a '
        'running Docker daemon:\n'
        '  npm install -g supabase\n'
        '  docker info',
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
      throw StateError(
        '`supabase functions serve` exited with code $exitCode. The '
        'supabase target needs the Supabase CLI 2.7.0 or later and a '
        'running Docker daemon:\n'
        '  docker info',
      );
    }
  }

  /// Starts the local Supabase stack when [supabaseStackNeedsStart] says it
  /// is down, so a fresh checkout only needs `aim dev`, not a separate
  /// `supabase start` run at a moment before there is anything to serve.
  ///
  /// Deliberately never stops what it starts here: the stack (and the
  /// database in it) can outlive this `aim dev` process and be shared with
  /// other tools, so only [stop] — which never touches the stack — governs
  /// this runner's own exit paths.
  Future<void> _ensureStackRunning() async {
    ProcessResult status;
    try {
      status = await Process.run('supabase', ['status']);
    } on ProcessException catch (e) {
      throw StateError(
        'Could not run `supabase status` (${e.message}). The supabase '
        'target needs the Supabase CLI 2.7.0 or later and a running '
        'Docker daemon:\n'
        '  npm install -g supabase\n'
        '  docker info',
      );
    }
    if (!supabaseStackNeedsStart(status.exitCode)) return;

    print(
      '🐳 The local Supabase stack is not running; aim dev is starting it.',
    );
    print('   This brings up the local stack (Postgres, auth, storage, ...).');
    print(
      '   The first run takes a few minutes and applies this project\'s '
      'migrations and seed.sql to the local database.',
    );
    print(
      '   It stays up after aim dev exits — run `supabase stop` when you '
      'want to stop it.',
    );
    print('');

    Process start;
    try {
      start = await Process.start('supabase', [
        'start',
      ], mode: ProcessStartMode.inheritStdio);
    } on ProcessException catch (e) {
      throw StateError(
        'Could not start `supabase start` (${e.message}). The supabase '
        'target needs the Supabase CLI 2.7.0 or later and a running '
        'Docker daemon:\n'
        '  npm install -g supabase\n'
        '  docker info',
      );
    }
    final exitCode = await start.exitCode;
    if (exitCode != 0) {
      throw StateError(
        '`supabase start` exited with code $exitCode. The supabase target '
        'needs the Supabase CLI 2.7.0 or later and a running Docker '
        'daemon:\n'
        '  npm install -g supabase\n'
        '  docker info',
      );
    }
    print('');
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
