/// The aim_cli release version.
///
/// This must equal the `version:` field in this package's `pubspec.yaml`.
/// `dart run release:bump` rewrites this constant. It has to live in
/// source, rather than being read from the pubspec at runtime, because
/// `aim_cli` is installed as a compiled executable (`dart install
/// aim_cli`), where the pubspec is not available.
const aimCliVersion = '0.4.0';
