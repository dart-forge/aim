/// Test-only helper for the integration suites in this directory.
///
/// Starts the Postgres containers these suites need (so nobody has to run
/// Docker Compose by hand first), and gives a socket failure on the first
/// connection a diagnosis that names the port instead of a wall of
/// low-level wire-protocol errors.
library;

import 'dart:io';

/// Path of the Compose file, relative to the package root — the working
/// directory `dart test` runs from for this package (`cd packages/aim_postgres
/// && dart test`).
const composeFile = 'test/integration/docker-compose.yml';

/// Starts (or confirms already-healthy) the Postgres containers these
/// integration suites connect to.
///
/// Runs `docker compose -f $composeFile up -d --wait`, which is idempotent
/// and fast once the containers are already up and healthy, so calling this
/// from every suite's `setUpAll` is fine even though several suites run
/// concurrently.
///
/// Deliberately does NOT stop the stack: several suites in this package run
/// against it at the same time, and a teardown here would stop containers
/// other suites still need mid-run. Stop the stack by hand when you are
/// done — see test/README.md.
///
/// Several suites also call this at once (dart test runs files
/// concurrently), so a couple of retries are built in: from a cold start,
/// two concurrent `docker compose up` invocations can both decide a
/// container needs creating and race the Docker daemon, and the loser sees
/// a spurious "container name already in use" instead of the container it
/// was about to create anyway. Retrying picks that up on the next pass,
/// once the winner has finished.
Future<void> ensurePostgresStack() async {
  ProcessResult? result;
  for (var attempt = 1; attempt <= 3; attempt++) {
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
        'Docker is required to run these integration suites (they are '
        'skipped by default; that is why you had to pass '
        '`-t integration --run-skipped` to get here). Could not run '
        '`docker compose`: $e',
      );
    }
    if (result.exitCode == 0) return;
    if (attempt < 3) {
      await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
    }
  }
  throw StateError(
    'docker compose -f $composeFile up -d --wait failed '
    '(exit ${result!.exitCode}):\n${result.stdout}\n${result.stderr}',
  );
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
/// with nothing pointing at the port. Wrap the first connection a suite
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
