/// Rewrites the string literal assigned to a `const <name> = '...'`
/// declaration (Dart or TypeScript/`.mts`) to [newVersion].
///
/// Used for version constants that have to live in source rather than be
/// read from a `pubspec.yaml` at runtime -- for example a compiled CLI
/// executable, or a `.mts` docs config file that has no pubspec at all.
/// `dart run release:bump` finds the declaration by [constName] and
/// replaces only the string literal it holds; the surrounding trailing
/// semicolon (present in Dart, absent in this repo's `.mts` style) is
/// preserved either way.
///
/// Returns [source] unchanged if no declaration named [constName] is found.
String bumpConstVersion(String source, String constName, String newVersion) {
  final pattern = RegExp(
    "const\\s+${RegExp.escape(constName)}\\s*=\\s*'[^']*'(;)?",
  );
  return source.replaceFirstMapped(
    pattern,
    (match) => "const $constName = '$newVersion'${match[1] ?? ''}",
  );
}
