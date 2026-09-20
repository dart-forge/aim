import 'dart:io';

import 'package:aim_cli/aim_cli.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late String previousCwd;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('aim_dev_');
    previousCwd = Directory.current.path;
    Directory.current = tmp;
    File(p.join(tmp.path, 'pubspec.yaml')).writeAsStringSync('''
name: my_fn
aim:
  target: functions
  entry: bin/server.dart
''');
    Directory(p.join(tmp.path, 'bin')).createSync();
    File(p.join(tmp.path, 'bin', 'server.dart'))
        .writeAsStringSync('void main() {}\n');
    File(p.join(tmp.path, 'firebase.json')).writeAsStringSync('{}\n');
  });

  tearDown(() async {
    Directory.current = previousCwd;
    await tmp.delete(recursive: true);
  });

  Future<void> dev(List<String> args) {
    final runner = CommandRunner<void>('aim', 'test')..addCommand(DevCommand());
    return runner.run(['dev', ...args]);
  }

  test('--port is refused for the functions target', () {
    // `firebase emulators:start` has no --port; silently ignoring it would
    // leave the user waiting on a port nothing listens on.
    expect(
      dev(['--port', '9999']),
      throwsA(
        isA<UsageException>().having(
          (e) => e.message,
          'message',
          allOf(contains('firebase.json'), contains('emulators')),
        ),
      ),
    );
  });

  test('a missing firebase.json is reported before the emulator starts', () {
    File(p.join(tmp.path, 'firebase.json')).deleteSync();
    expect(
      dev([]),
      throwsA(
        isA<UsageException>().having(
          (e) => e.message,
          'message',
          contains('firebase.json'),
        ),
      ),
    );
  });
}
