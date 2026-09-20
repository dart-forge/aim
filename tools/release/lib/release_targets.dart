import 'package:yaml/yaml.dart';

/// Whether a package's `pubspec.yaml` source holds it back from being
/// published, i.e. declares `publish_to: none`.
///
/// A held-back package stays in the release graph — its version still
/// moves in lockstep with everything else, and other packages may still
/// depend on it locally — but `dart run release:publish` does not push it
/// to pub.dev, and `dart run release:bump` leaves its CHANGELOG alone.
///
/// Any other value of `publish_to` (a custom hosted-pub URL, or the key
/// being absent altogether) returns `false`.
bool isPublishToNone(String pubspecYaml) {
  final yaml = loadYaml(pubspecYaml);
  if (yaml is! YamlMap) {
    return false;
  }
  return yaml['publish_to'] == 'none';
}

/// A package that is not held back but depends on one that is.
///
/// [dependent] will be published; [dependency] is one of the names in its
/// dependency list that will not be, because it is held back (see
/// [isPublishToNone]).
typedef SkippedDependencyViolation = ({String dependent, String dependency});

/// Every case where a package that will be published depends on a package
/// that is held back.
///
/// [dependenciesByPackage] maps each package name in the release graph to
/// the names of the other in-graph packages it depends on.
/// [skippedPackages] is the set of package names that are held back.
///
/// A held-back package's own dependencies are not checked: it is fine for
/// one held-back package to depend on another, since neither is being
/// pushed to pub.dev in this release.
List<SkippedDependencyViolation> skippedDependencyViolations({
  required Map<String, List<String>> dependenciesByPackage,
  required Set<String> skippedPackages,
}) {
  final violations = <SkippedDependencyViolation>[];
  for (final entry in dependenciesByPackage.entries) {
    final dependent = entry.key;
    if (skippedPackages.contains(dependent)) {
      continue;
    }
    for (final dependency in entry.value) {
      if (skippedPackages.contains(dependency)) {
        violations.add((dependent: dependent, dependency: dependency));
      }
    }
  }
  return violations;
}
