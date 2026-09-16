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
/// packages/aim_orm_codegen && dart test`).
const composeFile = 'test/integration/docker-compose.yml';

/// Starts (or confirms already-healthy) the Postgres container this
/// integration suite connects to.
///
/// Runs `docker compose -f $composeFile up -d --wait`, which is idempotent
/// and fast once the container is already up and healthy, so calling this
/// from the suite's `setUpAll` is fine.
///
/// Deliberately does NOT stop the stack afterwards — see test/README.md for
/// how to stop it by hand.
Future<void> ensurePostgresStack() async {
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
/// wrong process, so the failure doesn't surface as a plain connection
/// refused. It only appears once the Postgres wire protocol handshake
/// doesn't get the reply it expects — as a [SocketException] if that
/// process resets the connection, or as this package's own
/// "stream ended unexpectedly" if it just closes the socket — either way
/// with nothing pointing at the port. Wrap the first connection this suite
/// makes with this so that failure mode is diagnosed instead of just
/// reported.
Future<T> reportPortIfTaken<T>(
  Future<T> Function() connect, {
  required int port,
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
