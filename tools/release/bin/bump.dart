import 'dart:io';

import 'package:release/changelog.dart';
import 'package:release/pubspec_bump.dart';
import 'package:release/template_pins.dart';
import 'package:release/workspace.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// Aim packages that should be versioned together.
const aimPackagePrefixes = ['aim_'];

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run release:bump <version>');
    stderr.writeln('Example: dart run release:bump 0.1.0');
    exit(1);
  }

  final newVersion = args[0];

  if (!_isValidVersion(newVersion)) {
    stderr.writeln('Invalid version format: $newVersion');
    stderr.writeln('Expected format: x.y.z (e.g., 0.1.0, 1.0.0)');
    exit(1);
  }

  final memberPaths = _resolveWorkspaceMembers();

  final memberFiles = <File>[];
  for (final member in memberPaths) {
    final pubspec = File('$member/pubspec.yaml');
    if (pubspec.existsSync()) {
      memberFiles.add(pubspec);
    }
  }

  if (memberFiles.isEmpty) {
    stderr.writeln('No workspace member pubspec.yaml files found.');
    exit(1);
  }

  stdout.writeln('Bumping version to $newVersion\n');

  var packageCount = 0;
  for (final file in memberFiles) {
    if (_isTopLevelPackage(file.parent.path)) {
      _updatePubspec(file, newVersion);
      _updateChangelog(file.parent, newVersion);
      packageCount++;
    } else {
      _updateWorkspaceMemberDeps(file, newVersion);
    }
  }

  // Update aim_* pins embedded in the aim_cli scaffold templates
  _updateCliTemplates(newVersion);

  // Update docs version
  _updateDocsVersion(newVersion);

  stdout.writeln('\nDone! Updated $packageCount packages to $newVersion');
  stdout.writeln('\nNext steps:');
  stdout.writeln('  1. Review changes: git diff');
  stdout.writeln('  2. Commit: git commit -am "chore: bump version to $newVersion"');
  stdout.writeln(
    '  3. Tag: git tag $newVersion  (no "v" prefix: docs deploy and create_release expect 0.2.0-style tags)',
  );
}

bool _isValidVersion(String version) {
  final regex = RegExp(r'^\d+\.\d+\.\d+(-[\w.]+)?(\+[\w.]+)?$');
  return regex.hasMatch(version);
}

/// Returns the ordered list of workspace member directories to process.
///
/// Reads the `workspace:` list from the root `pubspec.yaml`. If the root
/// pubspec has no `workspace:` list (or doesn't exist), falls back to
/// scanning `packages/*` directly, matching the tool's original behaviour.
List<String> _resolveWorkspaceMembers() {
  final rootPubspec = File('pubspec.yaml');
  if (rootPubspec.existsSync()) {
    final members = workspaceMembers(rootPubspec.readAsStringSync());
    if (members.isNotEmpty) {
      return members;
    }
  }

  final packagesDir = Directory('packages');
  if (!packagesDir.existsSync()) {
    stderr.writeln('packages directory not found. Run from repository root.');
    exit(1);
  }

  return [
    for (final entity in packagesDir.listSync())
      if (entity is Directory) entity.path,
  ];
}

/// Whether [memberPath] is a top-level package directory, i.e. exactly one
/// segment under `packages/` (as opposed to a nested workspace member such
/// as a golden-test fixture, example, or tool).
bool _isTopLevelPackage(String memberPath) {
  final normalized = memberPath.replaceAll(Platform.pathSeparator, '/');
  if (!normalized.startsWith('packages/')) {
    return false;
  }
  final rest = normalized.substring('packages/'.length);
  return rest.isNotEmpty && !rest.contains('/');
}

void _updatePubspec(File file, String newVersion) {
  final content = file.readAsStringSync();
  final yaml = loadYaml(content) as YamlMap;

  final packageName = yaml['name'] as String;
  final oldVersion = yaml['version'] as String?;

  var updated = content;

  // Update version
  if (oldVersion != null) {
    final editor = YamlEditor(updated);
    editor.update(['version'], newVersion);
    updated = editor.toString();
    stdout.writeln('$packageName: $oldVersion → $newVersion');
  }

  _printAimConstraintChanges(yaml, newVersion);
  updated = bumpAimConstraints(updated, newVersion);

  file.writeAsStringSync(updated);
}

/// Updates only the `aim_*` dependency/dev_dependency constraints of a
/// workspace member that is not a top-level package (fixtures, examples,
/// tools). Does not touch `version:` or the CHANGELOG.
void _updateWorkspaceMemberDeps(File file, String newVersion) {
  final content = file.readAsStringSync();
  final yaml = loadYaml(content) as YamlMap;
  final packageName = (yaml['name'] as String?) ?? file.parent.path;

  stdout.writeln('$packageName (workspace member): deps only');
  _printAimConstraintChanges(yaml, newVersion);

  final updated = bumpAimConstraints(content, newVersion);
  file.writeAsStringSync(updated);
}

/// Prints the `  └─ <dep>: ^old → ^new` lines for every `aim_*`
/// dependency/dev_dependency constraint in [yaml] that will be bumped to
/// [newVersion]. Does not perform the update itself.
void _printAimConstraintChanges(YamlMap yaml, String newVersion) {
  final dependencies = yaml['dependencies'];
  if (dependencies is YamlMap) {
    for (final dep in dependencies.keys) {
      final depName = dep as String;
      if (_isAimPackage(depName)) {
        final currentVersion = dependencies[depName];
        if (currentVersion is String) {
          stdout.writeln('  └─ $depName: $currentVersion → ^$newVersion');
        }
      }
    }
  }

  final devDependencies = yaml['dev_dependencies'];
  if (devDependencies is YamlMap) {
    for (final dep in devDependencies.keys) {
      final depName = dep as String;
      if (_isAimPackage(depName)) {
        final currentVersion = devDependencies[depName];
        if (currentVersion is String) {
          stdout.writeln('  └─ $depName (dev): $currentVersion → ^$newVersion');
        }
      }
    }
  }
}

bool _isAimPackage(String packageName) {
  return aimPackagePrefixes.any((prefix) => packageName.startsWith(prefix));
}

const _repoUrl = 'https://github.com/dart-forge/aim';

final _unreleasedHeadingPattern = RegExp(
  r'^\s*##\s*unreleased\s*$',
  multiLine: true,
  caseSensitive: false,
);

void _updateChangelog(Directory packageDir, String newVersion) {
  final changelogFile = File('${packageDir.path}/CHANGELOG.md');
  final packageName = packageDir.path
      .split(Platform.pathSeparator)
      .where((segment) => segment.isNotEmpty)
      .last;

  if (!changelogFile.existsSync()) {
    // Create new CHANGELOG.md
    final content = '''# Changelog

## $newVersion

See [Release Notes]($_repoUrl/releases/tag/$newVersion)
''';
    changelogFile.writeAsStringSync(content);
    stdout.writeln('$packageName: CHANGELOG + $newVersion');
    return;
  }

  final content = changelogFile.readAsStringSync();
  final hadUnreleased = _unreleasedHeadingPattern.hasMatch(content);
  final updated = bumpChangelog(content, newVersion, repoUrl: _repoUrl);

  if (updated == content) {
    return;
  }

  changelogFile.writeAsStringSync(updated);
  if (hadUnreleased) {
    stdout.writeln('$packageName: CHANGELOG Unreleased → $newVersion');
  } else {
    stdout.writeln('$packageName: CHANGELOG + $newVersion');
  }
}

void _updateCliTemplates(String newVersion) {
  final templatesFile = File(
    'packages/aim_cli/lib/src/templates/templates.dart',
  );
  if (!templatesFile.existsSync()) {
    stdout.writeln(
      'Warning: aim_cli templates file not found, skipping template pins update.',
    );
    return;
  }

  final content = templatesFile.readAsStringSync();
  final pinRegex = RegExp(
    r'^(\s*)(aim_\w+): \^(\d+\.\d+\.\d+(?:-[\w.]+)?(?:\+[\w.]+)?)$',
    multiLine: true,
  );

  for (final match in pinRegex.allMatches(content)) {
    final depName = match[2]!;
    final oldVersion = match[3]!;
    if (oldVersion != newVersion) {
      stdout.writeln(
        'aim_cli templates: $depName ^$oldVersion → ^$newVersion',
      );
    }
  }

  final updated = bumpTemplatePins(content, newVersion);
  if (updated != content) {
    templatesFile.writeAsStringSync(updated);
  }
}

void _updateDocsVersion(String newVersion) {
  final configFile = File('docs/.vitepress/config.mts');
  if (!configFile.existsSync()) {
    return;
  }

  var content = configFile.readAsStringSync();
  var updated = false;

  // Update softwareVersion in JSON-LD
  final softwareVersionRegex = RegExp(r'"softwareVersion":\s*"[^"]*"');
  if (softwareVersionRegex.hasMatch(content)) {
    content = content.replaceFirst(
      softwareVersionRegex,
      '"softwareVersion": "$newVersion"',
    );
    updated = true;
  }

  // Update nav version (e.g., text: 'v0.0.6')
  final navVersionRegex = RegExp(r"text:\s*'v[\d.]+'");
  if (navVersionRegex.hasMatch(content)) {
    content = content.replaceFirst(navVersionRegex, "text: 'v$newVersion'");
    updated = true;
  }

  if (updated) {
    configFile.writeAsStringSync(content);
    stdout.writeln('docs: config.mts → v$newVersion');
  }
}
