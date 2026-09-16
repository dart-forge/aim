import 'package:yaml/yaml.dart';

/// Member directories listed under `workspace:` in a root pubspec.yaml, in
/// order.
///
/// Returns an empty list when [rootPubspecYaml] has no `workspace:` list
/// (or it is empty).
List<String> workspaceMembers(String rootPubspecYaml) {
  final yaml = loadYaml(rootPubspecYaml);
  if (yaml is! YamlMap) {
    return [];
  }

  final workspace = yaml['workspace'];
  if (workspace is! YamlList) {
    return [];
  }

  return [
    for (final entry in workspace)
      if (entry is String) entry,
  ];
}
