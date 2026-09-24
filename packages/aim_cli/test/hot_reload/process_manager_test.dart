import 'dart:io';

import 'package:aim_cli/src/hot_reload/process_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A server that records its pid and then stays up.
const _server = r'''
import 'dart:io';

void main() async {
  File(Platform.environment['AIM_TEST_PID_FILE']!)
      .writeAsStringSync('$pid\n', mode: FileMode.append, flush: true);
  await Future<void>.delayed(const Duration(days: 1));
}
''';

/// A server that watches `SIGTERM` without exiting, so only `SIGKILL` ends it.
/// A real app reaches this by installing a graceful shutdown that never
/// finishes; an orphan of one holds its port until it is force-killed.
const _ignoresSigterm = r'''
import 'dart:io';

void main() async {
  ProcessSignal.sigterm.watch().listen((_) {
    stdout.writeln('SIGTERM received, staying up');
  });
  File(Platform.environment['AIM_TEST_PID_FILE']!)
      .writeAsStringSync('$pid\n', mode: FileMode.append, flush: true);
  await Future<void>.delayed(const Duration(days: 1));
}
''';

/// These tests spawn real `dart run` processes: the bug they cover is a server
/// outliving the CLI, and only a real process can outlive anything.
void main() {
  late Directory tmp;
  late File pidFile;
  late String server;
  late String stubbornServer;
  late Map<String, String> environment;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('aim_process_manager_');
    pidFile = File(p.join(tmp.path, 'pids'));
    await pidFile.writeAsString('');
    server = p.join(tmp.path, 'server.dart');
    File(server).writeAsStringSync(_server);
    stubbornServer = p.join(tmp.path, 'stubborn_server.dart');
    File(stubbornServer).writeAsStringSync(_ignoresSigterm);
    environment = {...Platform.environment, 'AIM_TEST_PID_FILE': pidFile.path};
  });

  tearDown(() async {
    // A failing test must not leave a server holding a port.
    for (final pid in _recordedPids(pidFile)) {
      await Process.run('kill', ['-9', '$pid']);
    }
    await tmp.delete(recursive: true);
  });

  test(
    'stop() during a restart does not leave the new process running',
    () async {
      final manager = ProcessManager(
        entryPoint: server,
        environment: environment,
      );
      await manager.start();
      await _waitForPids(pidFile, 1);

      // Ctrl+C lands in the window between the kill and the respawn of a
      // hot reload restart.
      final restarting = manager.restart();
      await manager.stop();
      await restarting;

      expect(manager.isRunning, isFalse);
      expect(
        _recordedPids(pidFile),
        hasLength(1),
        reason: 'respawned after stop',
      );
      for (final pid in _recordedPids(pidFile)) {
        expect(
          await _isAlive(pid),
          isFalse,
          reason: 'pid $pid outlived stop()',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('start() after stop() does not spawn a process', () async {
    final manager = ProcessManager(
      entryPoint: server,
      environment: environment,
    );
    await manager.start();
    await _waitForPids(pidFile, 1);
    await manager.stop();

    await manager.start();

    expect(manager.isRunning, isFalse);
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(_recordedPids(pidFile), hasLength(1));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a second stop() waits for the process to be gone', () async {
    final manager = ProcessManager(
      entryPoint: stubbornServer,
      environment: environment,
    );
    await manager.start();
    final pids = await _waitForPids(pidFile, 1);

    final first = manager.stop();
    final second = manager.stop();
    await second;

    expect(await _isAlive(pids.single), isFalse);
    await first;
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('stop() force-kills a server that ignores SIGTERM', () async {
    final manager = ProcessManager(
      entryPoint: stubbornServer,
      environment: environment,
    );
    await manager.start();
    final pids = await _waitForPids(pidFile, 1);

    await manager.stop();

    expect(await _isAlive(pids.single), isFalse);
    expect(manager.isRunning, isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));
}

List<int> _recordedPids(File pidFile) => pidFile
    .readAsLinesSync()
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .map(int.parse)
    .toList();

Future<List<int>> _waitForPids(File pidFile, int count) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    final pids = _recordedPids(pidFile);
    if (pids.length >= count) return pids;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError(
    'only ${_recordedPids(pidFile).length} of $count '
    'processes reported a pid within 60s',
  );
}

Future<bool> _isAlive(int pid) async =>
    (await Process.run('kill', ['-0', '$pid'])).exitCode == 0;
