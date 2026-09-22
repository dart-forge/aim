import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:aim_cli/src/config/aim_config.dart';
import 'package:aim_cli/src/edge/edge_dev_runner.dart';
import 'package:aim_cli/src/functions/functions_dev_runner.dart';
import 'package:aim_cli/src/hot_reload/hot_reloader.dart';
import 'package:aim_cli/src/supabase/supabase_dev_runner.dart';
import 'package:aim_cli/src/utils/process_tree.dart';

class DevCommand extends Command {
  @override
  final name = 'dev';

  @override
  final description = 'Start development server (with hot reload support)';

  @override
  String get invocation => 'aim dev';

  DevCommand() {
    argParser.addOption(
      'entry',
      abbr: 'e',
      help: 'Server entry point (default: bin/server.dart)',
    );
    argParser.addOption('host', help: 'Server host (if configured)');
    argParser.addOption('port', abbr: 'p', help: 'Server port (if configured)');
    argParser.addFlag(
      'hot-reload',
      defaultsTo: true,
      negatable: true,
      help: 'Automatically restart server on file changes (default: enabled)',
    );
    argParser.addOption(
      'watch',
      help: 'Comma-separated list of directories to watch (default: lib,bin)',
    );
  }

  @override
  Future<void> run() async {
    // Check pubspec.yaml in current directory
    final pubspecFile = File('pubspec.yaml');

    if (!await pubspecFile.exists()) {
      print('Error: pubspec.yaml not found');
      print('Please run from the root directory of an Aim project');
      exit(1);
    }

    // Determine entry point
    final config = await AimConfig.load();

    if (config.target == AimTarget.functions) {
      // `firebase emulators:start` has no way to receive an entry point:
      // Firebase resolves it from firebase.json plus its own convention. So
      // this branch must not touch `--entry` / `aim.entry`, and it runs
      // before the entry-point resolution below, which is for the other
      // targets only.
      if (argResults?['port'] != null) {
        throw UsageException(
          '--port is not supported for target: functions. The Firebase '
          'emulator takes its port from firebase.json; set '
          'emulators.functions.port there.',
          invocation,
        );
      }
      final firebaseJson = File('firebase.json');
      if (!await firebaseJson.exists()) {
        throw UsageException(
          'firebase.json not found. It is required next to pubspec.yaml for '
          'the functions target. `aim create --target functions` writes '
          'one.',
          invocation,
        );
      }
      // Omit --project when .firebaserc names one, so the user's own choice
      // wins over a throwaway id.
      final hasFirebaserc = await File('.firebaserc').exists();
      final runner = FunctionsDevRunner(
        projectId: emulatorProjectId(
          hasFirebaserc: hasFirebaserc,
          packageName: config.packageName,
        ),
        environment: config.env,
      );
      print('🚀 Starting the Firebase emulator (functions)...');
      if (config.env.isNotEmpty) {
        print('🔧 Environment variables: ${config.env.keys.join(', ')}');
      }
      print('');
      _exitWhenSignalled(
        cleanup: runner.stop,
        stopping: '🛑 Stopping the emulator...',
        stopped: '✅ Stopped',
      );
      try {
        await runner.start();
      } catch (e) {
        print('❌ Error: ${e is StateError ? e.message : e}');
        exit(1);
      }
      return;
    }

    final entryPoint = config.resolveEntry(argResults?['entry'] as String?);

    // Check if entry point file exists
    final entryFile = File(entryPoint);
    if (!await entryFile.exists()) {
      print('Error: Entry point "$entryPoint" not found');
      exit(1);
    }

    // Hot reload configuration
    final hotReloadEnabled = argResults?['hot-reload'] as bool? ?? true;
    final watchPathsArg = argResults?['watch'] as String?;
    final watchPaths =
        watchPathsArg?.split(',') ??
        (config.target == AimTarget.workers ||
                config.target == AimTarget.supabase
            ? ['lib']
            : ['lib', 'bin']);

    if (config.target == AimTarget.workers) {
      if (config.env.isNotEmpty) {
        print(
          '⚠️  aim.env is ignored for target: workers. Use vars in '
          'wrangler.jsonc.',
        );
      }
      final portArg = argResults?['port'] as String?;
      int? port;
      if (portArg != null) {
        port = int.tryParse(portArg);
        if (port == null) {
          throw UsageException(
            '--port must be a number, got "$portArg"',
            invocation,
          );
        }
      }
      final runner = EdgeDevRunner(
        entry: entryPoint,
        outputDir: 'build/workers',
        watchPaths: watchPaths,
        port: port,
        watch: hotReloadEnabled,
      );
      print('🚀 Starting wrangler dev (Cloudflare workerd)...');
      print('📁 Entry point: $entryPoint');
      print('');
      _exitWhenSignalled(
        cleanup: runner.stop,
        stopping: '🛑 Stopping wrangler...',
        stopped: '✅ Stopped',
      );
      try {
        await runner.start();
      } catch (e) {
        print('❌ Error: $e');
        exit(1);
      }
      return;
    }

    if (config.target == AimTarget.supabase) {
      if (argResults?['port'] != null) {
        throw UsageException(
          '--port is not supported for target: supabase. '
          '`supabase functions serve` takes its port from '
          'supabase/config.toml.',
          invocation,
        );
      }
      final supabaseConfig = File('supabase/config.toml');
      if (!await supabaseConfig.exists()) {
        throw UsageException(
          'supabase/config.toml not found. It is required next to '
          'pubspec.yaml for the supabase target — `supabase functions '
          'serve` takes its port from it. `aim create --target supabase` '
          'writes one, or run `supabase init`.',
          invocation,
        );
      }
      if (config.env.isNotEmpty) {
        print(
          '⚠️  aim.env is ignored for target: supabase. Set environment '
          'variables locally in supabase/functions/.env (or with '
          '`supabase functions serve --env-file`), and after deploy with '
          '`supabase secrets set`.',
        );
      }
      final functionName = config.packageName;
      if (functionName == null || functionName.isEmpty) {
        throw UsageException(
          'pubspec.yaml has no "name". The supabase target uses it as the '
          'function name passed to `supabase functions serve`.',
          invocation,
        );
      }
      final runner = SupabaseDevRunner(
        entry: entryPoint,
        functionName: functionName,
        outputDir: 'supabase/functions/$functionName',
        watchPaths: watchPaths,
        watch: hotReloadEnabled,
      );
      print('🚀 Starting `supabase functions serve`...');
      print('📁 Entry point: $entryPoint');
      print('');
      _exitWhenSignalled(
        cleanup: runner.stop,
        stopping: '🛑 Stopping `supabase functions serve`...',
        stopped: '✅ Stopped',
      );
      try {
        await runner.start();
      } catch (e) {
        print('❌ Error: ${e is StateError ? e.message : e}');
        exit(1);
      }
      return;
    }

    // Get environment variables
    final envVars = config.env;

    // Get current environment variables and merge with aim.env settings
    final environment = Map<String, String>.from(Platform.environment)
      ..addAll(envVars);

    if (hotReloadEnabled) {
      await _runWithHotReload(
        entryPoint: entryPoint,
        environment: environment,
        envVars: envVars,
        watchPaths: watchPaths,
      );
    } else {
      await _runWithoutHotReload(
        entryPoint: entryPoint,
        environment: environment,
        envVars: envVars,
      );
    }
  }

  /// Run with hot reload
  Future<void> _runWithHotReload({
    required String entryPoint,
    required Map<String, String> environment,
    required Map<String, String> envVars,
    required List<String> watchPaths,
  }) async {
    print('🚀 Starting development server...');
    print('📁 Entry point: $entryPoint');
    if (envVars.isNotEmpty) {
      print('🔧 Environment variables: ${envVars.keys.join(', ')}');
    }
    print('👀 Watching files: ${watchPaths.join(', ')}');
    print('');

    final reloader = HotReloader(
      entryPoint: entryPoint,
      environment: environment,
      watchPaths: watchPaths,
    );

    _exitWhenSignalled(
      cleanup: reloader.stop,
      stopping: '🛑 Stopping server...',
      stopped: '✅ Server stopped',
    );

    try {
      await reloader.start();
    } catch (e) {
      // The server can be up even when the loop around it failed. Leaving it
      // behind holds the port with nothing watching it.
      await reloader.stop();
      print('❌ Error: $e');
      exit(1);
    }
  }

  /// Run without hot reload (existing behavior)
  Future<void> _runWithoutHotReload({
    required String entryPoint,
    required Map<String, String> environment,
    required Map<String, String> envVars,
  }) async {
    print('🚀 Starting development server...');
    print('📁 Entry point: $entryPoint');
    if (envVars.isNotEmpty) {
      print('🔧 Environment variables: ${envVars.keys.join(', ')}');
    }
    print('');

    // Start server with dart run
    final process = await Process.start(
      'dart',
      ['run', entryPoint],
      mode: ProcessStartMode.inheritStdio,
      environment: environment,
    );

    _exitWhenSignalled(
      cleanup: () => killProcessTree(process.pid),
      stopping: '🛑 Stopping server...',
      stopped: '✅ Server stopped',
    );

    // Wait for process to exit
    final exitCode = await process.exitCode;
    exit(exitCode);
  }
}

/// Runs [cleanup] when the CLI is asked to quit, then exits.
///
/// Ctrl+C reaches the server too, because it shares the CLI's process group,
/// but `kill <aim dev>` does not and neither does anything else that ends
/// only this process. Without [cleanup] the server stays up holding its port
/// with nothing left watching it, and the next `aim dev` cannot bind.
///
/// A second signal exits immediately, so a cleanup that hangs can still be
/// escaped with Ctrl+C.
void _exitWhenSignalled({
  required Future<void> Function() cleanup,
  required String stopping,
  required String stopped,
}) {
  var quitting = false;

  Future<void> quit(ProcessSignal signal) async {
    if (quitting) {
      exit(1);
    }
    quitting = true;
    print('\n$stopping');
    await cleanup();
    print(stopped);
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(quit);
  if (!Platform.isWindows) {
    // Watching SIGTERM replaces the default kill, so `kill <aim dev>` also
    // takes the server with it. Windows has no SIGTERM to watch.
    ProcessSignal.sigterm.watch().listen(quit);
  }
}
