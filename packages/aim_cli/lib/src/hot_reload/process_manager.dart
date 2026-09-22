import 'dart:io';

import 'package:aim_cli/src/utils/process_tree.dart';

/// Class responsible for managing server processes
class ProcessManager {
  final String _entryPoint;
  final Map<String, String> _environment;

  Process? _currentProcess;

  /// The kill in progress, shared by every caller that asks for one.
  ///
  /// Without this a second [stop] returns while the server is still up, and
  /// the caller — the Ctrl+C handler — exits the CLI before the kill lands.
  Future<void>? _killInFlight;

  /// Set by [stop]. [start] and [restart] do nothing afterwards, so a restart
  /// that was already running cannot respawn a server the CLI will not own.
  bool _stopped = false;

  ProcessManager({
    required String entryPoint,
    required Map<String, String> environment,
  }) : _entryPoint = entryPoint,
       _environment = environment;

  /// Start process
  Future<void> start() async {
    if (_stopped) {
      return;
    }
    if (_currentProcess != null) {
      throw StateError('Process is already running');
    }

    final Process process;
    try {
      process = await Process.start(
        'dart',
        ['run', _entryPoint],
        mode: ProcessStartMode.inheritStdio,
        environment: _environment,
      );
    } catch (e) {
      print('❌ Error: Failed to start server');
      print('   $e');
      rethrow;
    }

    _currentProcess = process;

    // `stop()` may have been called while the process was starting, which
    // leaves this one holding the port with nothing watching it.
    if (_stopped) {
      await _kill();
    }
  }

  /// Stop the server for good.
  ///
  /// Returns once the process is gone, including when a kill was already
  /// running. [start] and [restart] are no-ops afterwards.
  Future<void> stop() async {
    _stopped = true;
    await _kill();
  }

  /// Restart process
  Future<void> restart() async {
    if (_stopped) {
      return;
    }
    await _kill();
    await start();
  }

  /// Check if process is running
  bool get isRunning => _currentProcess != null;

  /// Kill the current process and wait for it to be gone.
  Future<void> _kill() {
    final inFlight = _killInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    return _killInFlight = _killCurrentProcess().whenComplete(() {
      _killInFlight = null;
    });
  }

  Future<void> _killCurrentProcess() async {
    final process = _currentProcess;
    if (process == null) {
      return;
    }

    // `dart run` may have children of its own, and a server that installs a
    // graceful shutdown can swallow SIGTERM: this escalates to SIGKILL, so
    // the port is free whatever the server does with the signal.
    await killProcessTree(process.pid);
    await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () => -1,
    );
    _currentProcess = null;
  }
}
