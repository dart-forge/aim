import 'dart:io';

import 'package:yaml/yaml.dart';

void main(List<String> args) async {
  final dryRun = args.contains('--dry-run');

  final packagesDir = Directory('packages');
  if (!packagesDir.existsSync()) {
    stderr.writeln('packages directory not found. Run from repository root.');
    exit(1);
  }

  // Collect package info
  final packages = <String, PackageInfo>{};
  for (final entity in packagesDir.listSync()) {
    if (entity is Directory) {
      final pubspec = File('${entity.path}/pubspec.yaml');
      if (pubspec.existsSync()) {
        final content = pubspec.readAsStringSync();
        final yaml = loadYaml(content) as YamlMap;
        final name = yaml['name'] as String;
        final deps = <String>[];

        final dependencies = yaml['dependencies'];
        if (dependencies is YamlMap) {
          for (final dep in dependencies.keys) {
            if ((dep as String).startsWith('aim_')) {
              deps.add(dep);
            }
          }
        }

        packages[name] = PackageInfo(
          name: name,
          path: entity.path,
          aimDependencies: deps,
        );
      }
    }
  }

  // Topological sort
  final sorted = _topologicalSort(packages);

  stdout.writeln('Publishing ${sorted.length} packages in order:\n');
  for (var i = 0; i < sorted.length; i++) {
    stdout.writeln('  ${i + 1}. ${sorted[i].name}');
  }
  stdout.writeln('');

  if (dryRun) {
    stdout.writeln('Dry run mode - validating packages...\n');
  }

  for (final pkg in sorted) {
    stdout.writeln('=' * 50);
    stdout.writeln('Publishing ${pkg.name}...');
    stdout.writeln('=' * 50);

    final result = await Process.run(
      'dart',
      [
        'pub',
        'publish',
        if (dryRun) '--dry-run',
        if (!dryRun) '--force',
      ],
      workingDirectory: pkg.path,
      runInShell: true,
    );

    stdout.write(result.stdout);
    if (result.stderr.toString().isNotEmpty) {
      stderr.write(result.stderr);
    }

    if (result.exitCode != 0) {
      stderr.writeln('\nFailed to publish ${pkg.name}');
      exit(1);
    }

    stdout.writeln('');
  }

  if (dryRun) {
    stdout.writeln('Dry run completed successfully!');
    stdout.writeln('Run without --dry-run to publish.');
  } else {
    stdout.writeln('All packages published successfully!');
  }
}

class PackageInfo {
  final String name;
  final String path;
  final List<String> aimDependencies;

  PackageInfo({
    required this.name,
    required this.path,
    required this.aimDependencies,
  });
}

List<PackageInfo> _topologicalSort(Map<String, PackageInfo> packages) {
  final sorted = <PackageInfo>[];
  final visited = <String>{};
  final visiting = <String>{};

  void visit(String name) {
    if (visited.contains(name)) return;
    if (visiting.contains(name)) {
      throw StateError('Circular dependency detected: $name');
    }

    final pkg = packages[name];
    if (pkg == null) return; // External dependency

    visiting.add(name);
    for (final dep in pkg.aimDependencies) {
      visit(dep);
    }
    visiting.remove(name);
    visited.add(name);
    sorted.add(pkg);
  }

  for (final name in packages.keys) {
    visit(name);
  }

  return sorted;
}
