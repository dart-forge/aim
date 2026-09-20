import 'dart:async';
import 'dart:io';

import 'package:aim_cli/aim_cli.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late String previousCwd;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('aim_build_');
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
  });

  tearDown(() async {
    Directory.current = previousCwd;
    await tmp.delete(recursive: true);
  });

  test(
    'the functions target builds nothing and points at firebase deploy',
    () async {
      final lines = <String>[];
      await runZoned(
        () {
          final runner = CommandRunner<void>('aim', 'test')
            ..addCommand(BuildCommand());
          return runner.run(['build']);
        },
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) => lines.add(line),
        ),
      );

      expect(lines.join('\n'), contains('firebase deploy --only functions'));
      // Nothing was compiled: a build directory would only hold an artifact the
      // deploy never uses.
      expect(Directory(p.join(tmp.path, 'build')).existsSync(), isFalse);
    },
  );
}
