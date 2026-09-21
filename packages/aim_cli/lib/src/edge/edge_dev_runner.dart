import 'dart:async';
import 'dart:io';

import 'package:aim_cli/src/edge/wasm_builder.dart';
import 'package:aim_cli/src/hot_reload/file_watcher.dart';
import 'package:aim_cli/src/utils/process_tree.dart';

/// Development loop for `aim.target: workers`.
///
/// Compiles the entry to wasm, starts `wrangler dev`, and recompiles on
/// file changes. wrangler reloads by itself because the JS entry module
/// imports the `.wasm` file.
class EdgeDevRunner {
  final String entry;
  final String outputDir;
  final List<String> watchPaths;
  final int? port;
  final bool watch;

  Process? _wrangler;
  FileWatcher? _watcher;
  bool _isBuilding = false;
  bool _buildRequested = false;
  bool _stopping = false;

  EdgeDevRunner({
    required this.entry,
    required this.outputDir,
    required this.watchPaths,
    this.port,
    this.watch = true,
  });

  Future<void> start() async {
    print('🔨 Compiling to WebAssembly...');
    await buildWasm(entry: entry, outputDir: outputDir);
    print('');

    try {
      _wrangler = await Process.start('npx', [
        '--yes',
        'wrangler@4',
        'dev',
        if (port != null) ...['--port', '$port'],
      ], mode: ProcessStartMode.inheritStdio);
    } on ProcessException catch (e) {
      throw StateError(
        'Could not start `npx wrangler@4 dev` (${e.message}). Node.js is '
        'required for the workers target; install Node and retry.',
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

    final exitCode = await _wrangler!.exitCode;
    await _watcher?.stop();
    if (_stopping) return;
    if (exitCode != 0) {
      throw StateError('wrangler dev exited with code $exitCode');
    }
  }

  Future<void> stop() async {
    _stopping = true;
    await _watcher?.stop();
    final wrangler = _wrangler;
    if (wrangler != null) {
      await killProcessTree(wrangler.pid);
      await wrangler.exitCode.timeout(
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
            '✅ Recompiled (${stopwatch.elapsedMilliseconds}ms); wrangler will reload',
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
