import 'dart:async';

import 'package:aim_database/aim_database.dart';
import 'package:test/test.dart';

class FakeConn {
  FakeConn(this.id);
  final int id;

  @override
  String toString() => 'FakeConn($id)';
}

/// Records every callback the pool makes so tests can assert on them.
class Harness {
  int _nextId = 0;
  final created = <FakeConn>[];
  final destroyed = <FakeConn>[];
  int validateCalls = 0;
  bool validateResult = true;
  Object? createError;

  /// When set, every validate() awaits this before returning.
  Completer<void>? validateGate;

  /// When set, validate() throws this instead of returning.
  Object? validateError;

  /// When set, every create() awaits this before proceeding.
  Completer<void>? createGate;

  /// When true, the next create() throws FormatException('gated failure')
  /// once.
  bool failNextCreate = false;

  /// Injected clock. Tests advance it with [advance].
  DateTime clock = DateTime(2026, 1, 1);

  void advance(Duration d) => clock = clock.add(d);

  Pool<FakeConn> pool(PoolOptions options) => Pool<FakeConn>(
        create: () async {
          final gate = createGate;
          if (gate != null) await gate.future;
          if (failNextCreate) {
            failNextCreate = false;
            throw const FormatException('gated failure');
          }
          final error = createError;
          if (error != null) throw error;
          final conn = FakeConn(_nextId++);
          created.add(conn);
          return conn;
        },
        validate: (_) async {
          validateCalls++;
          final gate = validateGate;
          if (gate != null) await gate.future;
          final error = validateError;
          if (error != null) throw error;
          return validateResult;
        },
        destroy: (conn) async => destroyed.add(conn),
        options: options,
        now: () => clock,
      );
}

/// Options that disable every timer-driven feature so tests are deterministic.
PoolOptions quietOptions({int maxConnections = 2}) => PoolOptions(
      maxConnections: maxConnections,
      acquireTimeout: const Duration(milliseconds: 200),
      idleTimeout: Duration.zero,
      maxLifetime: Duration.zero,
      validationInterval: const Duration(seconds: 30),
    );

void main() {
  group('PoolOptions', () {
    test('has documented defaults', () {
      final o = PoolOptions();
      expect(o.maxConnections, 10);
      expect(o.acquireTimeout, const Duration(seconds: 30));
      expect(o.idleTimeout, const Duration(minutes: 10));
      expect(o.maxLifetime, const Duration(minutes: 30));
      expect(o.validationInterval, const Duration(seconds: 30));
    });

    test('rejects maxConnections < 1', () {
      expect(() => PoolOptions(maxConnections: 0), throwsArgumentError);
    });

    test('rejects negative durations', () {
      expect(
        () => PoolOptions(acquireTimeout: const Duration(seconds: -1)),
        throwsArgumentError,
      );
      expect(
        () => PoolOptions(idleTimeout: const Duration(seconds: -1)),
        throwsArgumentError,
      );
      expect(
        () => PoolOptions(maxLifetime: const Duration(seconds: -1)),
        throwsArgumentError,
      );
      expect(
        () => PoolOptions(validationInterval: const Duration(seconds: -1)),
        throwsArgumentError,
      );
    });

    test('accepts Duration.zero', () {
      expect(
        () => PoolOptions(idleTimeout: Duration.zero, maxLifetime: Duration.zero),
        returnsNormally,
      );
    });
  });

  group('PoolTimeoutException', () {
    test('toString mentions waited time', () {
      const stats = PoolStats(
        total: 2,
        idle: 0,
        inUse: 2,
        waiting: 1,
        created: 2,
        destroyed: 0,
        timeouts: 1,
        validationFailures: 0,
      );
      final e = PoolTimeoutException(const Duration(milliseconds: 1500), stats);
      expect(e.toString(), contains('1500ms'));
      expect(e.toString(), contains('inUse: 2'));
    });
  });

  group('Pool acquire/release', () {
    late Harness h;
    late Pool<FakeConn> pool;

    setUp(() {
      h = Harness();
      pool = h.pool(quietOptions());
    });

    tearDown(() => pool.close());

    test('creates connections lazily up to maxConnections', () async {
      final a = await pool.acquire();
      final b = await pool.acquire();
      expect(a, isNot(same(b)));
      expect(h.created, hasLength(2));
      expect(pool.stats.total, 2);
      expect(pool.stats.inUse, 2);
      expect(pool.stats.idle, 0);
    });

    test('reuses the most recently released idle connection (LIFO)', () async {
      final a = await pool.acquire();
      final b = await pool.acquire();
      await pool.release(a);
      await pool.release(b);
      final next = await pool.acquire();
      expect(next, same(b));
      expect(h.created, hasLength(2));
      expect(pool.stats.idle, 1);
    });

    test('blocks when exhausted and hands the released connection to the waiter',
        () async {
      final a = await pool.acquire();
      await pool.acquire();
      var got = false;
      final waiting = pool.acquire().then((c) {
        got = true;
        return c;
      });
      await Future<void>.delayed(Duration.zero);
      expect(got, isFalse);
      expect(pool.stats.waiting, 1);

      await pool.release(a);
      final c = await waiting;
      expect(c, same(a));
      expect(pool.stats.idle, 0, reason: 'handed off directly, not parked');
      expect(pool.stats.waiting, 0);
      expect(h.created, hasLength(2), reason: 'no third connection created');
    });

    test('discard destroys the connection and replenishes for a waiter',
        () async {
      final a = await pool.acquire();
      await pool.acquire();
      final waiting = pool.acquire();
      await Future<void>.delayed(Duration.zero);

      await pool.release(a, discard: true);
      final c = await waiting;
      expect(h.destroyed, [a]);
      expect(c, isNot(same(a)));
      expect(h.created, hasLength(3));
      expect(pool.stats.destroyed, 1);
      expect(pool.stats.total, 2);
    });

    test('release of a connection not checked out throws', () async {
      expect(() => pool.release(FakeConn(99)), throwsStateError);
    });

    test('stats counts created', () async {
      await pool.acquire();
      expect(pool.stats.created, 1);
      expect(pool.stats.destroyed, 0);
      expect(pool.stats.timeouts, 0);
      expect(pool.stats.validationFailures, 0);
    });
  });

  group('Pool timeout and create failure', () {
    late Harness h;

    setUp(() => h = Harness());

    test('throws PoolTimeoutException when no connection frees up', () async {
      final pool = h.pool(quietOptions(maxConnections: 1));
      final a = await pool.acquire();

      await expectLater(
        pool.acquire(),
        throwsA(isA<PoolTimeoutException>()
            .having((e) => e.waited, 'waited', const Duration(milliseconds: 200))
            .having((e) => e.stats.inUse, 'stats.inUse', 1)),
      );
      expect(pool.stats.timeouts, 1);
      expect(pool.stats.waiting, 0, reason: 'timed-out waiter was removed');

      // A release after the timeout must park the connection, not hand it
      // to the dead waiter.
      await pool.release(a);
      expect(pool.stats.idle, 1);
      await pool.close();
    });

    test('create failure propagates and frees the slot', () async {
      final pool = h.pool(quietOptions(maxConnections: 1));
      h.createError = const FormatException('bad url');

      await expectLater(pool.acquire(), throwsFormatException);
      expect(pool.stats.total, 0);

      h.createError = null;
      final c = await pool.acquire();
      expect(c, isA<FakeConn>());
      expect(pool.stats.total, 1);
      await pool.close();
    });

    test('create failure while replenishing fails the waiter', () async {
      final pool = h.pool(quietOptions(maxConnections: 1));
      final a = await pool.acquire();
      final waiting = pool.acquire();
      await Future<void>.delayed(Duration.zero);

      h.createError = const FormatException('down');
      await pool.release(a, discard: true);

      await expectLater(waiting, throwsFormatException);
      expect(pool.stats.total, 0);
      await pool.close();
    });

    test('replenish opens at most one replacement per waiter', () async {
      final pool = h.pool(quietOptions(maxConnections: 3));
      final a = await pool.acquire();
      final b = await pool.acquire();
      final c = await pool.acquire();
      final waiting = pool.acquire();
      await Future<void>.delayed(Duration.zero);

      await pool.release(a, discard: true);
      await pool.release(b, discard: true);
      await waiting;
      expect(h.created, hasLength(4), reason: 'one replacement for one waiter');
      expect(pool.stats.total, 2);
      await pool.release(c);
      await pool.close();
    });

    test('waiter is replenished even while a direct create is in flight',
        () async {
      final pool = h.pool(quietOptions(maxConnections: 2));
      final a = await pool.acquire();
      h.createGate = Completer<void>();
      final x = pool.acquire(); // starts a direct create, blocked on the gate
      await Future<void>.delayed(Duration.zero);
      final y = pool.acquire(); // total == max → waiter
      await Future<void>.delayed(Duration.zero);
      expect(pool.stats.waiting, 1);

      await pool.release(a, discard: true); // frees a slot; must start a create for y
      h.createGate!.complete();
      final results = await Future.wait([x, y]);
      expect(results[0], isNot(same(results[1])));
      expect(h.created, hasLength(3));
      expect(pool.stats.waiting, 0);
      await pool.close();
    });

    test('direct create failure frees the slot and replenishes a waiter',
        () async {
      final pool = h.pool(quietOptions(maxConnections: 1));
      h.createGate = Completer<void>();
      h.failNextCreate = true;
      final x = pool.acquire(); // direct create, will fail once the gate opens
      await Future<void>.delayed(Duration.zero);
      final y = pool.acquire(); // waiter
      await Future<void>.delayed(Duration.zero);

      h.createGate!.complete();
      await expectLater(x, throwsFormatException);
      final c = await y; // replenished after the failure
      expect(c, isA<FakeConn>());
      expect(h.created, hasLength(1));
      expect(pool.stats.total, 1);
      await pool.release(c);
      await pool.close();
    });

    test(
        'a create that hangs past acquireTimeout throws and is destroyed when it lands',
        () async {
      final pool = h.pool(quietOptions(maxConnections: 1));
      h.createGate = Completer<void>();
      await expectLater(pool.acquire(), throwsA(isA<PoolTimeoutException>()));
      expect(pool.stats.total, 0);
      expect(pool.stats.timeouts, 1);

      h.createGate!.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(h.destroyed, hasLength(1), reason: 'late connection is destroyed');
      await pool.close();
    });
  });

  group('Pool validation and lifetime on acquire', () {
    late Harness h;

    setUp(() => h = Harness());

    test('skips validation when the connection was used recently', () async {
      final pool = h.pool(quietOptions());
      final a = await pool.acquire();
      await pool.release(a);
      h.advance(const Duration(seconds: 10)); // < validationInterval 30s
      await pool.acquire();
      expect(h.validateCalls, 0);
      await pool.close();
    });

    test('validates when idle for at least validationInterval', () async {
      final pool = h.pool(quietOptions());
      final a = await pool.acquire();
      await pool.release(a);
      h.advance(const Duration(seconds: 30));
      final again = await pool.acquire();
      expect(h.validateCalls, 1);
      expect(again, same(a));
      await pool.close();
    });

    test('validationInterval zero validates on every acquire', () async {
      final pool = h.pool(
        PoolOptions(
          maxConnections: 1,
          acquireTimeout: const Duration(milliseconds: 200),
          idleTimeout: Duration.zero,
          maxLifetime: Duration.zero,
          validationInterval: Duration.zero,
        ),
      );
      final a = await pool.acquire();
      await pool.release(a);
      await pool.acquire();
      expect(h.validateCalls, 1);
      await pool.close();
    });

    test('failed validation destroys and creates a replacement', () async {
      final pool = h.pool(quietOptions());
      final a = await pool.acquire();
      await pool.release(a);
      h.advance(const Duration(seconds: 30));
      h.validateResult = false;

      final b = await pool.acquire();
      expect(b, isNot(same(a)));
      expect(h.destroyed, [a]);
      expect(pool.stats.validationFailures, 1);
      expect(pool.stats.destroyed, 1);
      expect(pool.stats.created, 2);
      await pool.close();
    });

    test('idle connection past maxLifetime is destroyed without validation',
        () async {
      final pool = h.pool(
        PoolOptions(
          maxConnections: 2,
          acquireTimeout: const Duration(milliseconds: 200),
          idleTimeout: Duration.zero,
          maxLifetime: const Duration(minutes: 5),
          validationInterval: const Duration(seconds: 30),
        ),
      );
      final a = await pool.acquire();
      await pool.release(a);
      h.advance(const Duration(minutes: 5));

      final b = await pool.acquire();
      expect(b, isNot(same(a)));
      expect(h.destroyed, [a]);
      expect(h.validateCalls, 0);
      expect(pool.stats.validationFailures, 0);
      await pool.close();
    });

    test('a connection under validation still counts toward maxConnections',
        () async {
      final pool = h.pool(quietOptions(maxConnections: 1));
      final a = await pool.acquire();
      await pool.release(a);
      h.advance(const Duration(seconds: 30));
      h.validateGate = Completer<void>();

      final x = pool.acquire(); // pops a, blocked in validate()
      await Future<void>.delayed(Duration.zero);
      expect(pool.stats.total, 1);
      expect(pool.stats.inUse, 1);

      final y = pool.acquire(); // must wait, not create a second connection
      await Future<void>.delayed(Duration.zero);
      expect(pool.stats.waiting, 1);
      expect(h.created, hasLength(1));

      h.validateGate!.complete();
      final xConn = await x;
      expect(xConn, same(a));
      await pool.release(xConn);
      final yConn = await y;
      expect(yConn, same(a));
      expect(h.created, hasLength(1));
      await pool.release(yConn);
      await pool.close();
    });

    test('a validation that hangs past acquireTimeout counts as failed',
        () async {
      final pool = h.pool(quietOptions(maxConnections: 1));
      final a = await pool.acquire();
      await pool.release(a);
      h.advance(const Duration(seconds: 30));
      h.validateGate = Completer<void>();

      final b = await pool.acquire();
      expect(b, isNot(same(a)));
      expect(h.destroyed, [a]);
      expect(pool.stats.validationFailures, 1);
      h.validateGate!.complete();
      await pool.release(b);
      await pool.close();
    });

    test('a throwing validator counts as a failed validation', () async {
      final pool = h.pool(quietOptions());
      final a = await pool.acquire();
      await pool.release(a);
      h.advance(const Duration(seconds: 30));
      h.validateError = Exception('probe failed');

      final b = await pool.acquire();
      expect(b, isNot(same(a)));
      expect(h.destroyed, [a]);
      expect(pool.stats.validationFailures, 1);
      expect(pool.stats.total, 1);
      await pool.close();
    });
  });

  group('Pool eviction', () {
    late Harness h;

    setUp(() => h = Harness());

    PoolOptions evictOptions() => PoolOptions(
          maxConnections: 3,
          acquireTimeout: const Duration(milliseconds: 200),
          idleTimeout: const Duration(minutes: 1),
          maxLifetime: const Duration(minutes: 10),
          validationInterval: const Duration(hours: 1),
        );

    test('evictionIntervalFor is half of the smallest enabled duration', () {
      expect(
        Pool.evictionIntervalFor(evictOptions()),
        const Duration(seconds: 30),
      );
      expect(
        Pool.evictionIntervalFor(PoolOptions(
          idleTimeout: Duration.zero,
          maxLifetime: const Duration(minutes: 4),
        )),
        const Duration(minutes: 2),
      );
      expect(
        Pool.evictionIntervalFor(
          PoolOptions(idleTimeout: Duration.zero, maxLifetime: Duration.zero),
        ),
        isNull,
      );
      expect(
        Pool.evictionIntervalFor(PoolOptions(
          idleTimeout: const Duration(microseconds: 1),
          maxLifetime: Duration.zero,
        )),
        const Duration(milliseconds: 1),
        reason: 'sub-millisecond intervals are clamped to 1ms',
      );
    });

    test('evictExpired closes idle connections past idleTimeout', () async {
      final pool = h.pool(evictOptions());
      final a = await pool.acquire();
      final b = await pool.acquire();
      final c = await pool.acquire();
      await pool.release(a);
      await pool.release(b);
      h.advance(const Duration(minutes: 1));

      await pool.evictExpired();
      expect(h.destroyed, unorderedEquals([a, b]));
      expect(pool.stats.idle, 0);
      expect(pool.stats.inUse, 1, reason: 'in-use connections are untouched');
      await pool.release(c);
      await pool.close();
    });

    test('evictExpired leaves recently used idle connections alone', () async {
      final pool = h.pool(evictOptions());
      final a = await pool.acquire();
      await pool.release(a);
      h.advance(const Duration(seconds: 59));
      await pool.evictExpired();
      expect(h.destroyed, isEmpty);
      await pool.close();
    });

    test('evictExpired closes idle connections past maxLifetime', () async {
      final pool = h.pool(evictOptions());
      final a = await pool.acquire();
      // Keep it busy so idleTimeout never applies, then release just before
      // the lifetime check.
      h.advance(const Duration(minutes: 10));
      await pool.release(a);
      await pool.evictExpired();
      expect(h.destroyed, [a]);
      await pool.close();
    });
  });

  group('Pool close', () {
    late Harness h;

    setUp(() => h = Harness());

    test('destroys idle now and in-use connections on release', () async {
      final pool = h.pool(quietOptions(maxConnections: 2));
      final a = await pool.acquire();
      final b = await pool.acquire();
      await pool.release(a);

      await pool.close();
      expect(pool.isClosed, isTrue);
      expect(h.destroyed, [a]);
      expect(pool.stats.idle, 0);
      expect(pool.stats.inUse, 1);

      await pool.release(b);
      expect(h.destroyed, [a, b]);
      expect(pool.stats.total, 0);
    });

    test('fails waiters with StateError', () async {
      final pool = h.pool(quietOptions(maxConnections: 1));
      final a = await pool.acquire();
      final waiting = expectLater(pool.acquire(), throwsStateError);
      await Future<void>.delayed(Duration.zero);
      expect(pool.stats.waiting, 1);

      await pool.close();
      await waiting;
      expect(pool.stats.waiting, 0);
      await pool.release(a);
    });

    test('acquire after close throws', () async {
      final pool = h.pool(quietOptions());
      await pool.close();
      expect(() => pool.acquire(), throwsStateError);
    });

    test('acquire whose create finishes after close destroys and throws',
        () async {
      final gate = Completer<FakeConn>();
      final destroyed = <FakeConn>[];
      final pool = Pool<FakeConn>(
        create: () => gate.future,
        validate: (_) async => true,
        destroy: (c) async => destroyed.add(c),
        options: quietOptions(maxConnections: 1),
      );
      final acquiring = pool.acquire();
      await Future<void>.delayed(Duration.zero);
      expect(pool.stats.total, 1, reason: 'pending create is counted');

      await pool.close();
      gate.complete(FakeConn(1));

      await expectLater(acquiring, throwsStateError);
      expect(destroyed, hasLength(1));
      expect(pool.stats.total, 0);
    });

    test('close is idempotent', () async {
      final pool = h.pool(quietOptions());
      await pool.close();
      await expectLater(pool.close(), completes);
    });
  });
}
