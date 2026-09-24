import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:bench_runner/apps.dart';
import 'package:bench_runner/cloud/config.dart';
import 'package:bench_runner/cloud/redact.dart';
import 'package:bench_runner/cloud/render.dart';
import 'package:bench_runner/cloud/results.dart';
import 'package:bench_runner/cloud/runner.dart';
import 'package:bench_runner/cloud/targets.dart';
import 'package:bench_runner/environment.dart';
import 'package:bench_runner/oha.dart';
import 'package:bench_runner/process.dart';
import 'package:bench_runner/render.dart';
import 'package:bench_runner/results.dart';
import 'package:bench_runner/runner.dart';
import 'package:bench_runner/verify.dart';
import 'package:path/path.dart' as p;

const defaultPort = 18080;

Future<void> main(List<String> arguments) async {
  final runner =
      CommandRunner<void>(
          'bench',
          'Builds, verifies and measures the apps under bench/apps.',
        )
        ..addCommand(VerifyCommand())
        ..addCommand(RunCommand())
        ..addCommand(RenderCommand())
        ..addCommand(CloudCommand());
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
      await ensurePortFree(defaultPort);
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
      ..addOption(
        'connections',
        help: 'Concurrent connections.',
        defaultsTo: '64',
      )
      ..addOption(
        'runs',
        help: 'Runs per scenario (median is kept).',
        defaultsTo: '5',
      )
      ..addOption(
        'warmup',
        help: 'Warmup seconds per scenario (discarded).',
        defaultsTo: '3',
      );
  }

  @override
  final name = 'run';
  @override
  final description =
      'Build, verify and measure the apps; write bench/results/<date>-<label>.json.';

  @override
  Future<void> run() async {
    final args = argResults!;
    final settings = BenchSettings(
      duration: Duration(seconds: int.parse(args['duration'] as String)),
      connections: int.parse(args['connections'] as String),
      runs: int.parse(args['runs'] as String),
      warmup: Duration(seconds: int.parse(args['warmup'] as String)),
      arguments: args.arguments,
    );
    final oha = await ohaVersion();
    final now = DateTime.now().toUtc();
    final environment = await captureEnvironment();
    environment['aimCommit'] = await gitShortHead(benchRoot());

    final results = <AppResult>[];
    final skipped = <SkippedApp>[];
    for (final app in selectApps(args)) {
      stdout.writeln('== ${app.name}');
      try {
        results.add(
          await measureApp(
            app,
            settings: settings,
            port: defaultPort,
            build: buildApp,
          ),
        );
      } on StateError catch (e) {
        stdout.writeln('   skipped: ${e.message}');
        skipped.add(SkippedApp(app.name, e.message));
      }
      await Future<void>.delayed(settings.pause);
    }

    final bench = BenchResults(
      label: args['label'] as String,
      timestamp: now,
      environment: environment,
      settings: settings.toJson(oha),
      apps: results,
      skipped: skipped,
    );
    final file = resultsFile(bench.label, now);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(bench.toJson()),
    );
    stdout.writeln('wrote ${file.path}');
    stdout.writeln();
    stdout.write(renderMarkdown(bench));
    if (skipped.isNotEmpty) exitCode = 1;
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
    if (rest.length != 1) {
      throw UsageException('one results file is required', invocation);
    }
    final json = jsonDecode(
      File(rest.single).readAsStringSync(),
    ) as Map<String, Object?>;
    stdout.write(renderMarkdown(BenchResults.fromJson(json)));
  }
}

/// Resolves `--only` to the cloud targets to operate on.
List<CloudTarget> selectTargets(ArgResults results) {
  final only = results['only'] as String?;
  if (only == null) return cloudTargets;
  final target = findTarget(only);
  if (target == null) {
    throw UsageException(
      'unknown target "$only"; known: ${cloudTargets.map((t) => t.name).join(', ')}',
      '',
    );
  }
  return [target];
}

/// Loads `bench/cloud/config.yaml`. On failure (most commonly: the file
/// does not exist yet), prints the message — which names
/// `config.example.yaml` — and sets `exitCode` to 64 instead of throwing, so
/// callers can just check for null and return.
Future<CloudConfig?> loadCloudConfigOrNull() async {
  final file = File(p.join(cloudRoot().path, 'config.yaml'));
  try {
    return await loadCloudConfig(file);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exitCode = 64;
    return null;
  }
}

/// `<command> --version`, captured and trimmed; `'not installed'` instead
/// of throwing when the executable cannot be found, so a missing tool never
/// fails the whole run over a version string nobody strictly needs.
Future<String> toolVersion(List<String> command) async {
  try {
    final output = await runCapturing(command, workingDirectory: cloudRoot());
    return output.trim();
  } on ProcessException {
    return 'not installed';
  }
}

/// Truncates [s] to 300 characters, the same limit [scrubReason] applies —
/// used when a skip reason has no resolved base to scrub against.
String _truncated(String s) => s.length > 300 ? s.substring(0, 300) : s;

/// `bench/results/cloud-<date>-<label>.json`, with [label] sanitized the
/// same way stage 1's results file name is.
File cloudResultsFile(String label, DateTime now) {
  final date = now.toUtc().toIso8601String().substring(0, 10);
  final safeLabel = label.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
  return File(p.join(benchRoot().path, 'results', 'cloud-$date-$safeLabel.json'));
}

class CloudCommand extends Command<void> {
  CloudCommand() {
    addSubcommand(CloudVerifyCommand());
    addSubcommand(CloudRunCommand());
    addSubcommand(CloudRenderCommand());
  }

  @override
  final name = 'cloud';
  @override
  final description = 'Deploy and measure the cloud targets under bench/cloud.';
}

class CloudVerifyCommand extends Command<void> {
  CloudVerifyCommand() {
    argParser.addOption('only', help: 'Verify a single target (e.g. workers/aim).');
  }

  @override
  final name = 'verify';
  @override
  final description = 'Deploy each cloud target once and check it answers every scenario.';

  @override
  Future<void> run() async {
    final config = await loadCloudConfigOrNull();
    if (config == null) return;

    var failed = false;
    for (final target in selectTargets(argResults!)) {
      stdout.writeln('== ${target.name}');
      final dir = Directory(p.join(cloudRoot().path, target.directory));
      for (final step in target.build(config)) {
        await runStep(step, workingDirectory: dir);
      }
      stdout.writeln('   ${target.name}: deploying');
      final output = await runCapturing(target.deploy(config), workingDirectory: dir);
      final base = target.url(config, output);
      if (base == null) {
        failed = true;
        stdout.writeln('   ${target.name}: could not find the deployed URL in the deploy output');
        continue;
      }
      final mismatches = await verifyApp(base);
      if (mismatches.isEmpty) {
        stdout.writeln('   ${target.name}: ok');
      } else {
        failed = true;
        for (final m in mismatches) {
          stdout.writeln('   ${target.name}: $m');
        }
      }
    }
    if (failed) exitCode = 1;
  }
}

class CloudRunCommand extends Command<void> {
  CloudRunCommand() {
    argParser
      ..addOption('only', help: 'Measure a single target (e.g. workers/aim).')
      ..addOption('label', help: 'Results file suffix; defaults to the config label.')
      ..addOption('cycles', help: 'Deploy-and-measure cycles.', defaultsTo: '5')
      ..addOption('requests', help: 'Sequential requests per scenario.', defaultsTo: '100');
  }

  @override
  final name = 'run';
  @override
  final description =
      'Deploy, verify and measure the cloud targets; write bench/results/cloud-<date>-<label>.json.';

  @override
  Future<void> run() async {
    final config = await loadCloudConfigOrNull();
    if (config == null) return;

    final args = argResults!;
    final settings = CloudSettings(
      cycles: int.parse(args['cycles'] as String),
      requests: int.parse(args['requests'] as String),
      arguments: args.arguments,
    );
    final label = (args['label'] as String?) ?? config.label;
    final now = DateTime.now().toUtc();

    final environment = await captureEnvironment();
    environment['wrangler'] = await toolVersion(['npx', '--yes', 'wrangler@4', '--version']);
    environment['supabase'] = await toolVersion(['supabase', '--version']);
    environment['firebase'] = await toolVersion(['firebase', '--version']);
    environment['node'] = await toolVersion(['node', '--version']);
    environment['aimCommit'] = await gitShortHead(benchRoot());
    environment['measuredFrom'] = config.label;

    final results = <TargetResult>[];
    final skipped = <SkippedApp>[];
    final targets = selectTargets(args);
    for (var i = 0; i < targets.length; i++) {
      final target = targets[i];
      stdout.writeln('== ${target.name}');
      Uri? base;
      try {
        results.add(
          await measureTarget(
            target,
            config,
            settings,
            log: stdout.writeln,
            onBaseResolved: (b) => base = b,
          ),
        );
      } on StateError catch (e) {
        // base is only set once a URL has been resolved for this target;
        // a failure before that point (an unrecognized deploy output, for
        // example) has nothing to scrub.
        final reason = base == null ? _truncated(e.message) : scrubReason(e.message, base!, target.name);
        stdout.writeln('   skipped: $reason');
        skipped.add(SkippedApp(target.name, reason));
      }
      if (i < targets.length - 1) {
        await Future<void>.delayed(settings.pauseBetweenTargets);
      }
    }

    final cloudResults = CloudResults(
      label: label,
      timestamp: now,
      environment: environment,
      settings: settings.toJson(),
      targets: results,
      skipped: skipped,
    );

    final json = const JsonEncoder.withIndent('  ').convert(cloudResults.toJson());
    final leaks = leakedIdentifiers(json, config);
    if (leaks.isNotEmpty) {
      // Report the category labels only (never the raw values that
      // leakedIdentifiers matched) so this message itself cannot leak an
      // identifier through stderr.
      stderr.writeln('results not written: they would contain ${leaks.join(', ')}');
      exitCode = 1;
      return;
    }

    final file = cloudResultsFile(cloudResults.label, now);
    await file.parent.create(recursive: true);
    await file.writeAsString(json);
    stdout.writeln('wrote ${file.path}');
    stdout.writeln();
    stdout.write(renderCloudMarkdown(cloudResults));
    if (skipped.isNotEmpty) exitCode = 1;
  }
}

class CloudRenderCommand extends Command<void> {
  @override
  final name = 'render';
  @override
  final description = 'Print a cloud results JSON file as Markdown tables.';
  @override
  String get invocation => 'bench cloud render <results.json>';

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      throw UsageException('one results file is required', invocation);
    }
    final json = jsonDecode(
      File(rest.single).readAsStringSync(),
    ) as Map<String, Object?>;
    stdout.write(renderCloudMarkdown(CloudResults.fromJson(json)));
  }
}
