import 'package:aim_cli/src/hot_reload/process_manager.dart';
import 'package:aim_cli/src/hot_reload/file_watcher.dart';

/// Integration class for hot reload functionality
class HotReloader {
  final String _entryPoint;
  final Map<String, String> _environment;
  final List<String> _watchPaths;

  // Created on first use rather than in `start()`, so that `stop()` is safe
  // to call whether or not the loop got as far as starting.
  late final ProcessManager _processManager = ProcessManager(
    entryPoint: _entryPoint,
    environment: _environment,
  );
  late final FileWatcher _fileWatcher = FileWatcher(
    watchPaths: _watchPaths,
    onChanged: _onFileChanged,
  );

  bool _isReloading = false;
  bool _stopped = false;

  HotReloader({
    required String entryPoint,
    required Map<String, String> environment,
    List<String>? watchPaths,
  }) : _entryPoint = entryPoint,
       _environment = environment,
       _watchPaths = watchPaths ?? ['lib', 'bin'];

  /// Start hot reload
  Future<void> start() async {
    // Start process
    await _processManager.start();

    // Start file watching
    await _fileWatcher.start();

    // Wait until process terminates
    // (Exits with Ctrl+C or error)
    await Future<void>.delayed(const Duration(days: 365));
  }

  /// Stop hot reload
  Future<void> stop() async {
    _stopped = true;
    await _fileWatcher.stop();
    await _processManager.stop();
  }

  /// Handle file changes
  Future<void> _onFileChanged() async {
    if (_isReloading || _stopped) {
      return; // Already reloading, or the CLI is on its way out
    }

    _isReloading = true;

    try {
      print('📝 File change detected');
      print('🔄 Restarting server...');
      print('');

      final stopwatch = Stopwatch()..start();

      await _processManager.restart();

      stopwatch.stop();
      print('');
      print('✅ Restart complete (${stopwatch.elapsedMilliseconds}ms)');
      print('');
    } catch (e) {
      print('❌ Error: Failed to restart');
      print('   $e');
      print('');
    } finally {
      _isReloading = false;
    }
  }
}
