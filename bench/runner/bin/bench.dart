import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:bench_runner/apps.dart';
import 'package:bench_runner/process.dart';
import 'package:bench_runner/verify.dart';

const defaultPort = 18080;

Future<void> main(List<String> arguments) async {
  final runner = CommandRunner<void>(
    'bench',
    'Builds, verifies and measures the apps under bench/apps.',
  )..addCommand(VerifyCommand());
  try {
    await runner.run(arguments);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exitCode = 64;
  }
}

/// Resolves `--only` to the apps to operate on.
List<AppSpec> selectApps(ArgResults results) {
  final only = results['only'] as String?;
  if (only == null) return apps;
  final app = findApp(only);
  if (app == null) {
    throw UsageException(
      'unknown app "$only"; known: ${apps.map((a) => a.name).join(', ')}',
      '',
    );
  }
  return [app];
}

/// Runs an app's prebuild steps and compiles it to `bench/build/<name>`.
Future<File> buildApp(AppSpec app) async {
  final dir = appDirectory(app);
  stdout.writeln('== build ${app.name}');
  await runStep(['dart', 'pub', 'get'], workingDirectory: dir);
  for (final step in app.prebuild) {
    await runStep(step, workingDirectory: dir);
  }
  return compileExe(
    workingDirectory: appBuildDirectory(app),
    entry: app.entry,
    output: appBinary(app),
  );
}

class VerifyCommand extends Command<void> {
  VerifyCommand() {
    argParser.addOption('only', help: 'Verify a single app.');
  }

  @override
  final name = 'verify';
  @override
  final description = 'Build each app and check it answers every scenario.';

  @override
  Future<void> run() async {
    var failed = false;
    for (final app in selectApps(argResults!)) {
      final binary = await buildApp(app);
      final process = await startServer(
        binary,
        port: defaultPort,
        workingDirectory: appBuildDirectory(app),
      );
      final base = Uri.parse('http://127.0.0.1:$defaultPort');
      try {
        await waitUntilReady(base);
        final mismatches = await verifyApp(base);
        if (mismatches.isEmpty) {
          stdout.writeln('   ${app.name}: ok');
        } else {
          failed = true;
          for (final m in mismatches) {
            stdout.writeln('   ${app.name}: $m');
          }
        }
      } finally {
        await stopServer(process);
      }
    }
    if (failed) exitCode = 1;
  }
}
