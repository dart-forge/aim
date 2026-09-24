import 'dart:io';

import 'package:path/path.dart' as p;

/// One framework under test.
class AppSpec {
  const AppSpec({
    required this.name,
    required this.directory,
    required this.entry,
    this.prebuild = const [],
    this.buildDirectory = '.',
    this.lockPackages = const [],
  });

  /// Short name; also the results key and the `--only` value.
  final String name;

  /// Relative to `bench/apps/`.
  final String directory;

  /// Commands run in the app directory before compiling (e.g. a framework's
  /// own build step). Each is `[executable, ...arguments]`.
  final List<List<String>> prebuild;

  /// Directory, relative to the app directory, that `dart compile exe` runs
  /// in and that [entry] is relative to.
  final String buildDirectory;

  /// Dart entry point relative to [buildDirectory].
  final String entry;

  /// Packages whose resolved versions are read from the app's pubspec.lock
  /// and recorded with the results.
  final List<String> lockPackages;
}

const List<AppSpec> apps = [
  AppSpec(name: 'dart_io', directory: 'dart_io', entry: 'bin/server.dart'),
];

/// `bench/`, resolved from this package's location (`bench/runner`).
Directory benchRoot() {
  final scriptDir = p.dirname(p.fromUri(Platform.script));
  // bin/ → runner/ → bench/
  return Directory(p.normalize(p.join(scriptDir, '..', '..')));
}

Directory appDirectory(AppSpec app) =>
    Directory(p.join(benchRoot().path, 'apps', app.directory));

Directory appBuildDirectory(AppSpec app) =>
    Directory(p.join(appDirectory(app).path, app.buildDirectory));

File appBinary(AppSpec app) =>
    File(p.join(benchRoot().path, 'build', app.name));

AppSpec? findApp(String name) {
  for (final app in apps) {
    if (app.name == name) return app;
  }
  return null;
}
