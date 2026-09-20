import 'dart:io';

import 'package:aim_cli/src/config/aim_config.dart';
import 'package:aim_cli/src/edge/wasm_builder.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as path;

class BuildCommand extends Command {
  @override
  final name = 'build';

  @override
  final description = 'Compile the server for production deployment';

  @override
  String get invocation => 'aim build [options]';

  BuildCommand() {
    argParser.addOption(
      'entry',
      abbr: 'e',
      help: 'Server entry point (default: pubspec.yaml aim.entry or bin/server.dart)',
    );

    argParser.addOption(
      'output',
      abbr: 'o',
      help:
          'Output path (default: build/server, or the build/edge '
          'directory for target: edge)',
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
      print('ℹ️  Nothing to build for target: functions.');
      print('');
      print('`firebase deploy --only functions` compiles the function for');
      print('Linux on this machine and uploads the result, so a build here');
      print('would only leave behind an artifact the deploy never reads.');
      print('');
      print('Next steps:');
      print('  aim dev                            # run it in the emulator');
      print('  firebase deploy --only functions   # compile and deploy');
      print('');
      return;
    }

    if (config.target == AimTarget.edge) {
      final outputDir = argResults?['output'] as String? ?? 'build/edge';
      print('🔨 Compiling to WebAssembly for Cloudflare workerd...');
      print('📁 Entry point: $entryPoint');
      print('📦 Output: $outputDir/');
      print('');
      try {
        await buildWasm(entry: entryPoint, outputDir: outputDir);
      } on WasmBuildException catch (e) {
        print('');
        print('❌ $e');
        exit(e.exitCode);
      }
      print('');
      print('✅ Build successful!');
      print('');
      print('📦 Output: $outputDir/main.wasm, $outputDir/main.mjs');
      print('');
      print('Next steps:');
      print('  npx wrangler@4 dev       # run locally');
      print('  npx wrangler@4 deploy    # deploy to Cloudflare');
      print('');
      return;
    }

    // Determine output path
    String outputPath = argResults?['output'] as String? ?? 'build/server';

    // Create output directory if it doesn't exist
    final outputDir = Directory(path.dirname(outputPath));
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    // Build compile command
    final compileArgs = ['compile', 'exe', entryPoint, '-o', outputPath];

    // Display build information
    print('🔨 Compiling for production...');
    print('📁 Entry point: $entryPoint');
    print('📦 Output: $outputPath');
    print('');

    // Execute compilation
    final process = await Process.start(
      'dart',
      compileArgs,
      mode: ProcessStartMode.inheritStdio,
    );

    final exitCode = await process.exitCode;

    if (exitCode != 0) {
      print('');
      print('❌ Compilation failed');
      exit(exitCode);
    }

    // Success message
    print('');
    print('✅ Build successful!');
    print('');
    print('📦 Executable: $outputPath');
    print('');
    print('Next steps:');
    print('  # Run locally');
    print('  ./$outputPath');
    print('');
    print('  # Build Docker image');
    print('  docker build -t my-app .');
    print('');
  }
}
