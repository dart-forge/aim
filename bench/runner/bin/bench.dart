import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:bench_runner/apps.dart';
import 'package:bench_runner/environment.dart';
import 'package:bench_runner/oha.dart';
import 'package:bench_runner/process.dart';
import 'package:bench_runner/render.dart';
import 'package:bench_runner/results.dart';
import 'package:bench_runner/runner.dart';
import 'package:bench_runner/verify.dart';

const defaultPort = 18080;

Future<void> main(List<String> arguments) async {
  final runner = CommandRunner<void>(
    'bench',
    'Builds, verifies and measures the apps under bench/apps.',
  )
    ..addCommand(VerifyCommand())
    ..addCommand(RunCommand())
    ..addCommand(RenderCommand());
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

class RunCommand extends Command<void> {
  RunCommand() {
    argParser
      ..addOption('only', help: 'Measure a single app.')
      ..addOption('label', help: 'Results file suffix.', defaultsTo: 'local')
      ..addOption('duration', help: 'Seconds per run.', defaultsTo: '10')
      ..addOption('connections', help: 'Concurrent connections.', defaultsTo: '64')
      ..addOption('runs', help: 'Runs per scenario (median is kept).', defaultsTo: '5')
      ..addOption('warmup', help: 'Warmup seconds per scenario (discarded).', defaultsTo: '3');
  }

  @override
  final name = 'run';
  @override
  final description = 'Build, verify and measure the apps; write bench/results/<date>-<label>.json.';

  @override
  Future<void> run() async {
    final args = argResults!;
    final settings = BenchSettings(
      duration: Duration(seconds: int.parse(args['duration'] as String)),
      connections: int.parse(args['connections'] as String),
      runs: int.parse(args['runs'] as String),
      warmup: Duration(seconds: int.parse(args['warmup'] as String)),
    );
    final oha = await ohaVersion();
    final now = DateTime.now().toUtc();
    final environment = await captureEnvironment();
    environment['aimCommit'] = await gitShortHead(benchRoot());

    final results = <AppResult>[];
    for (final app in selectApps(args)) {
      stdout.writeln('== ${app.name}');
      results.add(await measureApp(app, settings: settings, port: defaultPort, build: buildApp));
      await Future<void>.delayed(settings.pause);
    }

    final bench = BenchResults(
      label: args['label'] as String,
      timestamp: now,
      environment: environment,
      settings: settings.toJson(oha),
      apps: results,
    );
    final file = resultsFile(bench.label, now);
    await file.parent.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(bench.toJson()));
    stdout.writeln('wrote ${file.path}');
    stdout.writeln();
    stdout.write(renderMarkdown(bench));
  }
}

class RenderCommand extends Command<void> {
  @override
  final name = 'render';
  @override
  final description = 'Print a results JSON file as Markdown tables.';
  @override
  String get invocation => 'bench render <results.json>';

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) throw UsageException('one results file is required', invocation);
    final json = jsonDecode(File(rest.single).readAsStringSync()) as Map<String, Object?>;
    stdout.write(renderMarkdown(BenchResults.fromJson(json)));
  }
}
