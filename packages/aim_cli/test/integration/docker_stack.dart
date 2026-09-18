/// Test-only helper for the integration suite in this directory.
///
/// Starts the Postgres container that suite needs (so nobody has to run
/// Docker Compose by hand first), and gives a socket failure on the first
/// connection a diagnosis that names the port instead of a wall of
/// low-level wire-protocol errors.
library;

import 'dart:io';

/// Path of the Compose file, relative to the package root — the working
/// directory `dart test` runs from for this package (`cd
/// packages/aim_cli && dart test`).
const composeFile = 'test/integration/docker-compose.yml';

/// The port the Compose file publishes.
const postgresPort = 15438;

/// The URL the commands under test connect with.
const databaseUrl = 'postgres://test:test@localhost:$postgresPort/test_db';

/// Starts (or confirms already-healthy) the Postgres container this
/// integration suite connects to.
///
/// Runs `docker compose -f $composeFile up -d --wait`, which is idempotent
/// and fast once the container is already up and healthy, so calling this
/// from the suite's `setUpAll` is fine.
///
/// Deliberately does NOT stop the stack afterwards: other suites in this
/// repository share the same habit, and stopping a container another test
/// run is using would break it.
Future<void> ensurePostgresStack() async {
  if (!File(composeFile).existsSync()) {
    throw StateError(
      'Could not find $composeFile. This suite expects `dart test` to run '
      'from the package root (cd packages/aim_cli && dart test -t '
      'integration --run-skipped), because the Compose file path is '
      'relative to it. Current directory: ${Directory.current.path}',
    );
  }

  ProcessResult result;
  try {
    result = await Process.run('docker', [
      'compose',
      '-f',
      composeFile,
      'up',
      '-d',
      '--wait',
    ]);
  } on ProcessException catch (e) {
    throw StateError(
      'Docker is required to run this integration suite (it is skipped by '
      'default; that is why you had to pass `-t integration --run-skipped` '
      'to get here). Could not run `docker compose`: $e',
    );
  }
  if (result.exitCode != 0) {
    throw StateError(
      'docker compose -f $composeFile up -d --wait failed '
      '(exit ${result.exitCode}):\n${result.stdout}\n${result.stderr}',
    );
  }
}

/// Runs [connect] and, if it fails, rethrows with the port, the Compose
/// file that publishes it, and the command to find out what is actually
/// listening there.
///
/// A port already held by another process is the failure mode that gives
/// the least useful raw error: the TCP handshake can succeed against the
/// wrong process, so the failure only appears once the Postgres wire
/// protocol handshake does not get the reply it expects, with nothing
/// pointing at the port.
Future<T> reportPortIfTaken<T>(
  Future<T> Function() connect, {
  int port = postgresPort,
}) async {
  try {
    return await connect();
  } on Exception catch (e) {
    throw StateError(
      'Could not reach Postgres on localhost:$port ($e)\n'
      'This port is published by $composeFile.\n'
      'Another process may be holding it instead of the test container — '
      'check with:\n'
      '  lsof -nP -iTCP:$port -sTCP:LISTEN',
    );
  }
}
