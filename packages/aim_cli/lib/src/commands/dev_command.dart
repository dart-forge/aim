import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:aim_cli/src/config/aim_config.dart';
import 'package:aim_cli/src/edge/edge_dev_runner.dart';
import 'package:aim_cli/src/functions/functions_dev_runner.dart';
import 'package:aim_cli/src/hot_reload/hot_reloader.dart';

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
    final entryPoint = config.resolveEntry(argResults?['entry'] as String?);

    // Check if entry point file exists
    final entryFile = File(entryPoint);
    if (!await entryFile.exists()) {
      print('Error: Entry point "$entryPoint" not found');
      exit(1);
    }

    if (config.target == AimTarget.functions) {
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
          'firebase.json not found. The functions target needs it next to '
          'pubspec.yaml, with "source": "." in its functions entry. '
          '`aim create --target functions` writes one.',
          invocation,
        );
      }
      // Omit --project when .firebaserc names one, so the user's own choice
      // wins over a throwaway id.
      final hasFirebaserc = await File('.firebaserc').exists();
      final runner = FunctionsDevRunner(
        projectId: hasFirebaserc ? null : demoProjectId(config.packageName),
        environment: config.env,
      );
      print('🚀 Starting the Firebase emulator (functions)...');
      print('📁 Entry point: $entryPoint');
      if (config.env.isNotEmpty) {
        print('🔧 Environment variables: ${config.env.keys.join(', ')}');
      }
      print('');
      ProcessSignal.sigint.watch().listen((_) async {
        print('\n🛑 Stopping the emulator...');
        await runner.stop();
        print('✅ Stopped');
        exit(0);
      });
      try {
        await runner.start();
      } catch (e) {
        print('❌ Error: $e');
        exit(1);
      }
      return;
    }

    // Hot reload configuration
    final hotReloadEnabled = argResults?['hot-reload'] as bool? ?? true;
    final watchPathsArg = argResults?['watch'] as String?;
    final watchPaths =
        watchPathsArg?.split(',') ??
        (config.target == AimTarget.edge ? ['lib'] : ['lib', 'bin']);

    if (config.target == AimTarget.edge) {
      if (config.env.isNotEmpty) {
        print(
          '⚠️  aim.env is ignored for target: edge. Use vars in wrangler.jsonc.',
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
        outputDir: 'build/edge',
        watchPaths: watchPaths,
        port: port,
        watch: hotReloadEnabled,
      );
      print('🚀 Starting wrangler dev (Cloudflare workerd)...');
      print('📁 Entry point: $entryPoint');
      print('');
      ProcessSignal.sigint.watch().listen((_) async {
        print('\n🛑 Stopping wrangler...');
        await runner.stop();
        print('✅ Stopped');
        exit(0);
      });
      try {
        await runner.start();
      } catch (e) {
        print('❌ Error: $e');
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

    // Ctrl+C handler
    ProcessSignal.sigint.watch().listen((signal) async {
      print('\n🛑 Stopping server...');
      await reloader.stop();
      print('✅ Server stopped');
      exit(0);
    });

    try {
      await reloader.start();
    } catch (e) {
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

    // Wait for process to exit
    final exitCode = await process.exitCode;
    exit(exitCode);
  }
}
