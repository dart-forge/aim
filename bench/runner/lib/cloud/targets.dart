import 'dart:io';

import 'package:bench_runner/cloud/config.dart';
import 'package:bench_runner/cloud/parsers.dart';
import 'package:path/path.dart' as p;

enum CloudRuntime { workers, supabase, functions }

enum Variant { aim, native }

/// One deployable thing under `bench/cloud`: how to build it, deploy it,
/// read its URL out of the deploy output, and measure what it uploaded.
class CloudTarget {
  const CloudTarget({
    required this.runtime,
    required this.variant,
    required this.directory,
    required this.region,
    required this.build,
    required this.deploy,
    required this.url,
    required this.size,
  });

  final CloudRuntime runtime;
  final Variant variant;

  /// Relative to `cloudRoot()`.
  final String directory;

  final String region;

  /// Commands run, in order, in [directory] before `deploy`. Each is
  /// `[executable, ...arguments]`.
  final List<List<String>> Function(CloudConfig) build;

  /// The command run in [directory] to deploy.
  final List<String> Function(CloudConfig) deploy;

  /// Extracts the deployed origin from the deploy command's captured output.
  final Uri? Function(CloudConfig, String deployOutput) url;

  /// Measures what was uploaded, from [dir] (the target's directory) and/or
  /// the deploy command's captured output.
  final Future<UploadSize> Function(Directory dir, String deployOutput) size;

  String get name => '${runtime.name}/${variant.name}';
}

List<CloudTarget> cloudTargets = [
  CloudTarget(
    runtime: CloudRuntime.workers,
    variant: Variant.aim,
    directory: 'workers/aim',
    region: 'nearest Cloudflare colo',
    build: (c) => [
      ['dart', 'pub', 'get'],
      ['dart', 'compile', 'wasm', 'lib/main.dart', '-o', 'build/workers/main.wasm'],
      ['dart', 'run', '../../../runner/bin/export_compiled_app.dart', 'build/workers/main.mjs'],
    ],
    deploy: (c) => ['npx', '--yes', 'wrangler@4', 'deploy', '--name', '${c.workersNamePrefix}-aim'],
    url: (c, out) => parseWranglerUrl(out),
    size: (dir, out) async =>
        parseWranglerUpload(out) ??
        await sizeOfFiles([
          File('${dir.path}/build/workers/main.wasm'),
          File('${dir.path}/build/workers/main.mjs'),
          File('${dir.path}/src/index.mjs'),
        ]),
  ),
  CloudTarget(
    runtime: CloudRuntime.workers,
    variant: Variant.native,
    directory: 'workers/native',
    region: 'nearest Cloudflare colo',
    build: (c) => const [],
    deploy: (c) => ['npx', '--yes', 'wrangler@4', 'deploy', '--name', '${c.workersNamePrefix}-native'],
    url: (c, out) => parseWranglerUrl(out),
    size: (dir, out) async =>
        parseWranglerUpload(out) ?? await sizeOfFiles([File('${dir.path}/src/index.mjs')]),
  ),
  CloudTarget(
    runtime: CloudRuntime.supabase,
    variant: Variant.aim,
    directory: 'supabase',
    region: 'Southeast Asia (Singapore)',
    build: (c) => [
      ['dart', 'pub', 'get', '--directory', 'aim_app'],
      ['dart', 'compile', 'wasm', 'aim_app/lib/main.dart', '-o', 'supabase/functions/aim_bench_aim/main.wasm'],
      ['dart', 'run', '../../runner/bin/export_compiled_app.dart', 'supabase/functions/aim_bench_aim/main.mjs'],
    ],
    deploy: (c) =>
        ['supabase', 'functions', 'deploy', 'aim_bench_aim', '--project-ref', c.supabaseProjectRef, '--no-verify-jwt'],
    url: (c, out) => Uri.parse('https://${c.supabaseProjectRef}.supabase.co/functions/v1/aim_bench_aim'),
    size: (dir, out) => sizeOfFiles([
      for (final f in ['main.wasm', 'main.mjs', 'index.ts']) File('${dir.path}/supabase/functions/aim_bench_aim/$f'),
    ]),
  ),
  CloudTarget(
    runtime: CloudRuntime.supabase,
    variant: Variant.native,
    directory: 'supabase',
    region: 'Southeast Asia (Singapore)',
    build: (c) => const [],
    deploy: (c) => [
      'supabase',
      'functions',
      'deploy',
      'aim_bench_native',
      '--project-ref',
      c.supabaseProjectRef,
      '--no-verify-jwt',
    ],
    url: (c, out) => Uri.parse('https://${c.supabaseProjectRef}.supabase.co/functions/v1/aim_bench_native'),
    size: (dir, out) => sizeOfFiles([File('${dir.path}/supabase/functions/aim_bench_native/index.ts')]),
  ),
  CloudTarget(
    runtime: CloudRuntime.functions,
    variant: Variant.aim,
    directory: 'functions',
    region: 'us-central1',
    build: (c) => [
      ['dart', 'pub', 'get', '--directory', 'aim'],
    ],
    deploy: (c) => [
      'firebase',
      'deploy',
      '--only',
      'functions:aim',
      '--project',
      c.firebaseProject,
      '--non-interactive',
      '--force',
    ],
    url: (c, out) => parseFirebaseFunctionUrl(out, 'benchAim'),
    size: (dir, out) async =>
        UploadSize(bytes: await sizeOfDirectory(Directory('${dir.path}/aim/build/cli/linux_x64/bundle'))),
  ),
  CloudTarget(
    runtime: CloudRuntime.functions,
    variant: Variant.native,
    directory: 'functions',
    region: 'us-central1',
    build: (c) => [
      ['npm', 'install', '--prefix', 'native'],
    ],
    deploy: (c) => [
      'firebase',
      'deploy',
      '--only',
      'functions:native',
      '--project',
      c.firebaseProject,
      '--non-interactive',
      '--force',
    ],
    url: (c, out) => parseFirebaseFunctionUrl(out, 'benchNative'),
    size: (dir, out) => sizeOfFiles([File('${dir.path}/native/index.js'), File('${dir.path}/native/package.json')]),
  ),
];

CloudTarget? findTarget(String name) {
  for (final t in cloudTargets) {
    if (t.name == name) return t;
  }
  return null;
}

/// `bench/cloud`, resolved from this package's location (`bench/runner`), the
/// same way `benchRoot()` in `lib/apps.dart` resolves `bench/`.
Directory cloudRoot() {
  final scriptDir = p.dirname(p.fromUri(Platform.script));
  // bin/ → runner/ → bench/ → cloud/
  return Directory(p.normalize(p.join(scriptDir, '..', '..', 'cloud')));
}
