import 'dart:async';
import 'dart:io';

/// Runs [command] to completion, streaming its output; throws on failure.
Future<void> runStep(
  List<String> command, {
  required Directory workingDirectory,
}) async {
  final process = await Process.start(
    command.first,
    command.skip(1).toList(),
    workingDirectory: workingDirectory.path,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) {
    throw ProcessException(
      command.first,
      command.skip(1).toList(),
      'exited with $code in ${workingDirectory.path}',
      code,
    );
  }
}

/// `dart compile exe <entry> -o <output>` run inside [workingDirectory].
Future<File> compileExe({
  required Directory workingDirectory,
  required String entry,
  required File output,
}) async {
  await output.parent.create(recursive: true);
  await runStep(
    ['dart', 'compile', 'exe', entry, '-o', output.absolute.path],
    workingDirectory: workingDirectory,
  );
  return output;
}

/// Starts [binary] with `PORT` set; stdout/stderr are drained and discarded
/// so logging (which no app should do) cannot skew the measurement.
Future<Process> startServer(
  File binary, {
  required int port,
  required Directory workingDirectory,
}) async {
  final process = await Process.start(
    binary.absolute.path,
    const [],
    workingDirectory: workingDirectory.path,
    environment: {'PORT': '$port'},
  );
  discardOutput(process);
  return process;
}

/// Subscribes to [process]'s stdout and stderr and discards everything.
///
/// A child's stdout/stderr pipe is only read once something subscribes to
/// it; left unsubscribed, a child that writes enough to fill the OS pipe
/// buffer blocks on write() and the whole run hangs. This keeps that from
/// ever happening without echoing the app's output into the runner's own
/// console (unlike `ProcessStartMode.inheritStdio`).
void discardOutput(Process process) {
  unawaited(process.stdout.drain<void>());
  unawaited(process.stderr.drain<void>());
}

/// Throws [StateError] if [port] is already bound on the loopback
/// interface, so a leftover process from a previous run is never mistaken
/// for the one about to be launched.
Future<void> ensurePortFree(int port) async {
  try {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    await socket.close();
  } on SocketException {
    throw StateError(
      'port $port is already in use; is a previous app still running?',
    );
  }
}

/// Polls [url] until it answers 200; returns the time that took.
Future<Duration> waitUntilReady(
  Uri url, {
  Duration timeout = const Duration(seconds: 30),
  Duration interval = const Duration(milliseconds: 1),
}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  final watch = Stopwatch()..start();
  try {
    while (watch.elapsed < timeout) {
      try {
        final response = await client.getUrl(url).then((r) => r.close());
        await response.drain<void>();
        if (response.statusCode == 200) return watch.elapsed;
      } on SocketException {
        // Not listening yet.
      } on HttpException {
        // Connection dropped while starting up.
      }
      await Future<void>.delayed(interval);
    }
    throw TimeoutException('$url did not answer 200 within $timeout');
  } finally {
    client.close(force: true);
  }
}

/// Physical memory footprint in KB, or null if the process is gone.
///
/// Reads `ps -o rss=` where the caller is allowed to see it; recent macOS
/// blocks that column for unentitled callers (`ps: rss: requires
/// entitlement`), in which case this falls back to `/usr/bin/footprint`.
/// `footprint`'s number is the physical footprint, which is not strictly
/// the same thing as RSS, but is the closest available substitute.
Future<int?> memoryFootprintKb(int pid) async {
  final ps = await Process.run('ps', ['-o', 'rss=', '-p', '$pid']);
  if (ps.exitCode == 0) {
    final kb = int.tryParse((ps.stdout as String).trim());
    if (kb != null) return kb;
  }
  final footprint = await Process.run('footprint', ['$pid']);
  if (footprint.exitCode != 0) return null;
  return parseFootprintKb(footprint.stdout as String);
}

/// Parses the KB value out of `footprint`'s `Footprint: <n> <unit>` header
/// line, converting MB/GB/B to KB (rounded to the nearest integer). Returns
/// null when no such line is present.
int? parseFootprintKb(String footprintOutput) {
  final match = RegExp(r'Footprint:\s*([\d.]+)\s*(KB|MB|GB|bytes|B)\b')
      .firstMatch(footprintOutput);
  if (match == null) return null;
  final value = double.tryParse(match.group(1)!);
  if (value == null) return null;
  final kb = switch (match.group(2)) {
    'GB' => value * 1024 * 1024,
    'MB' => value * 1024,
    'KB' => value,
    'bytes' || 'B' => value / 1024,
    _ => null,
  };
  return kb?.round();
}

/// SIGTERM, then SIGKILL if the process is still alive after two seconds.
Future<void> stopServer(Process process) async {
  process.kill(ProcessSignal.sigterm);
  try {
    await process.exitCode.timeout(const Duration(seconds: 2));
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
  }
}
