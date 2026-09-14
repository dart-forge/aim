import 'dart:io';

import 'package:release/template_pins.dart';

/// The aim-specific half of a release bump. Run right after `rask bump <version>`:
/// rewrites the aim_* pins in the aim_cli scaffold templates and the version
/// shown in the docs. `rask bump` owns pubspec versions, member constraints
/// and CHANGELOGs.
void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run release:after_bump <version>');
    exit(1);
  }
  final newVersion = args[0];
  if (!_isValidVersion(newVersion)) {
    stderr.writeln('Invalid version format: $newVersion (expected x.y.z)');
    exit(1);
  }
  _updateCliTemplates(newVersion);
  _updateDocsVersion(newVersion);
  stdout.writeln(
    'Done. Next: review `git diff`, commit, tag $newVersion, then `rask publish` and `dart run release:create_release $newVersion`.',
  );
}

bool _isValidVersion(String version) {
  final regex = RegExp(r'^\d+\.\d+\.\d+(-[\w.]+)?(\+[\w.]+)?$');
  return regex.hasMatch(version);
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
      stdout.writeln('aim_cli templates: $depName ^$oldVersion → ^$newVersion');
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
