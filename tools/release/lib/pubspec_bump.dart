import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// Aim packages that should be versioned together.
const _aimPackagePrefixes = ['aim_'];

const _constraintSections = ['dependencies', 'dev_dependencies'];

/// Rewrites `aim_*` `dependencies`/`dev_dependencies` entries in
/// [pubspecYaml] whose value is a plain version-constraint string (e.g.
/// `aim_orm: ^0.1.1`) to `^newVersion`.
///
/// Map-valued entries (e.g. `aim_server: {path: ../aim_server}`, as used by
/// `examples/*`) are left untouched, as is everything else in the document
/// (including `version:`).
String bumpAimConstraints(String pubspecYaml, String newVersion) {
  final yaml = loadYaml(pubspecYaml) as YamlMap;
  final editor = YamlEditor(pubspecYaml);

  for (final section in _constraintSections) {
    final deps = yaml[section];
    if (deps is! YamlMap) {
      continue;
    }

    for (final dep in deps.keys) {
      final depName = dep as String;
      if (!_isAimPackage(depName)) {
        continue;
      }

      final currentVersion = deps[depName];
      if (currentVersion is String) {
        editor.update([section, depName], '^$newVersion');
      }
    }
  }

  return editor.toString();
}

bool _isAimPackage(String packageName) {
  return _aimPackagePrefixes.any(packageName.startsWith);
}
