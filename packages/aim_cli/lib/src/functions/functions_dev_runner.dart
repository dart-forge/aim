import 'dart:io';

import 'package:aim_cli/src/utils/process_tree.dart';

/// A throwaway Firebase project id for the emulator, derived from
/// [packageName].
///
/// The emulator needs a project id even when there is no real project. Ids
/// beginning with `demo-` are the documented way to say "local only": the
/// emulator suite then refuses to reach production resources, so a typo here
/// cannot touch anything real.
String demoProjectId(String? packageName) {
  final slug = (packageName ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.isEmpty) return 'demo-aim';
  final id = 'demo-$slug';
  if (id.length <= 30) return id;
  return id.substring(0, 30).replaceAll(RegExp(r'-+$'), '');
}

/// The `--project` to pass the Firebase CLI, or null to let `.firebaserc`
/// name it.
String? emulatorProjectId({
  required bool hasFirebaserc,
  required String? packageName,
}) => hasFirebaserc ? null : demoProjectId(packageName);

/// Development loop for `aim.target: functions`.
///
/// Starts the Firebase emulator and waits for it. There is deliberately no
/// file watcher here: the emulator runs `build_runner watch` for Dart
/// functions itself, so a second rebuild loop would race it. This is the
/// opposite of the edge target, where wrangler cannot regenerate the
/// artifact it serves and the CLI has to.
class FunctionsDevRunner {
  /// Passed to the Firebase CLI as `--project`, or omitted when null because
  /// `.firebaserc` already names one.
  final String? projectId;

  /// Extra variables for the emulator process, which the function process it
  /// spawns inherits.
  final Map<String, String> environment;

  Process? _firebase;
  bool _stopping = false;

  FunctionsDevRunner({this.projectId, this.environment = const {}});

  Future<void> start() async {
    try {
      _firebase = await Process.start(
        'firebase',
        [
          'emulators:start',
          '--only',
          'functions',
          if (projectId != null) ...['--project', projectId!],
        ],
        mode: ProcessStartMode.inheritStdio,
        environment: {...Platform.environment, ...environment},
      );
    } on ProcessException catch (e) {
      throw StateError(
        'Could not start `firebase emulators:start` (${e.message}). The '
        'functions target needs the Firebase CLI with its Dart support '
        'switched on:\n'
        '  npm install -g firebase-tools\n'
        '  firebase login\n'
        '  firebase experiments:enable dartfunctions',
      );
    }

    final exitCode = await _firebase!.exitCode;
    if (_stopping) return;
    if (exitCode != 0) {
      throw StateError(
        'firebase emulators:start exited with code $exitCode. This usually '
        'means the Dart experiment is off; run '
        '`firebase experiments:enable dartfunctions`.',
      );
    }
  }

  Future<void> stop() async {
    _stopping = true;
    final firebase = _firebase;
    if (firebase != null) {
      await killProcessTree(firebase.pid);
      await firebase.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => -1,
      );
    }
  }
}
