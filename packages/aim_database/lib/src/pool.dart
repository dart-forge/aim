import 'dart:async';
import 'dart:collection';

/// Tuning knobs for [Pool].
class PoolOptions {
  PoolOptions({
    this.maxConnections = 10,
    this.acquireTimeout = const Duration(seconds: 30),
    this.idleTimeout = const Duration(minutes: 10),
    this.maxLifetime = const Duration(minutes: 30),
    this.validationInterval = const Duration(seconds: 30),
  }) {
    if (maxConnections < 1) {
      throw ArgumentError.value(
        maxConnections,
        'maxConnections',
        'must be at least 1',
      );
    }
    _requireNonNegative(acquireTimeout, 'acquireTimeout');
    _requireNonNegative(idleTimeout, 'idleTimeout');
    _requireNonNegative(maxLifetime, 'maxLifetime');
    _requireNonNegative(validationInterval, 'validationInterval');
  }

  /// Upper bound on connections (idle + in use + being created).
  final int maxConnections;

  /// Bound for each blocking phase of [Pool.acquire]: validating an idle
  /// connection, opening a new one, and waiting for a release. Each phase is
  /// bounded separately, so a single acquire can take up to three times this
  /// in the worst case. Exceeding it throws [PoolTimeoutException] (or, for
  /// validation, discards the connection and moves on).
  final Duration acquireTimeout;

  /// Idle connections unused for longer than this are closed.
  /// [Duration.zero] disables idle eviction.
  final Duration idleTimeout;

  /// Connections older than this are closed once they become idle.
  /// [Duration.zero] disables lifetime eviction.
  final Duration maxLifetime;

  /// An idle connection unused for at least this long is validated before
  /// being handed out. [Duration.zero] validates on every acquire.
  final Duration validationInterval;

  static void _requireNonNegative(Duration d, String name) {
    if (d.isNegative) {
      throw ArgumentError.value(d, name, 'must not be negative');
    }
  }
}

/// Immutable snapshot of a [Pool]'s state.
class PoolStats {
  const PoolStats({
    required this.total,
    required this.idle,
    required this.inUse,
    required this.waiting,
    required this.created,
    required this.destroyed,
    required this.timeouts,
    required this.validationFailures,
  });

  /// Connections that exist right now, including ones still being created.
  final int total;

  /// Connections sitting idle in the pool.
  final int idle;

  /// Connections currently checked out.
  final int inUse;

  /// Callers blocked in [Pool.acquire].
  final int waiting;

  /// Total connections ever created.
  final int created;

  /// Total connections ever destroyed.
  final int destroyed;

  /// Total [PoolTimeoutException]s thrown.
  final int timeouts;

  /// Total idle connections discarded because validation failed.
  final int validationFailures;

  @override
  String toString() =>
      'PoolStats(total: $total, idle: $idle, inUse: $inUse, waiting: $waiting, '
      'created: $created, destroyed: $destroyed, timeouts: $timeouts, '
      'validationFailures: $validationFailures)';
}

/// Thrown by [Pool.acquire] when no connection became available within
/// [PoolOptions.acquireTimeout].
class PoolTimeoutException implements Exception {
  PoolTimeoutException(this.waited, this.stats);

  /// How long the caller waited.
  final Duration waited;

  /// Pool state at the moment of the timeout.
  final PoolStats stats;

  @override
  String toString() =>
      'PoolTimeoutException: no connection available after '
      '${waited.inMilliseconds}ms ($stats)';
}

class _PooledEntry<C> {
  _PooledEntry(this.conn, this.createdAt) : lastUsedAt = createdAt;

  final C conn;
  final DateTime createdAt;
  DateTime lastUsedAt;
}

/// A bounded pool of reusable connections of type [C].
///
/// The pool knows nothing about the connection type. Callers supply
/// [create], [validate] and [destroy]. Connections are handed out with
/// [acquire] and must always be returned with [release]; pass
/// `discard: true` when the connection is known to be unusable.
class Pool<C> {
  Pool({
    required this.create,
    required this.validate,
    required this.destroy,
    required this.options,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    final interval = evictionIntervalFor(options);
    if (interval != null) {
      _evictionTimer =
          Timer.periodic(interval, (_) => unawaited(evictExpired()));
    }
  }

  /// Opens a new connection.
  final Future<C> Function() create;

  /// Returns `true` if the idle connection is still usable.
  final Future<bool> Function(C conn) validate;

  /// Closes a connection. Errors thrown here are swallowed.
  final Future<void> Function(C conn) destroy;

  final PoolOptions options;
  final DateTime Function() _now;

  final List<_PooledEntry<C>> _idle = [];
  final Map<C, _PooledEntry<C>> _inUse = {};
  final Queue<Completer<C>> _waiters = Queue();

  /// Connections whose [create] has not completed yet. Counted in [_total]
  /// so concurrent acquires cannot overshoot [PoolOptions.maxConnections].
  int _pending = 0;

  /// Creates started by [_replenishForWaiters] that have not yet completed.
  int _pendingForWaiters = 0;

  Timer? _evictionTimer;

  bool _closed = false;
  int _created = 0;
  int _destroyed = 0;
  int _timeouts = 0;
  int _validationFailures = 0;

  int get _total => _idle.length + _inUse.length + _pending;

  /// `true` once [close] has been called.
  bool get isClosed => _closed;

  PoolStats get stats => PoolStats(
        total: _total,
        idle: _idle.length,
        inUse: _inUse.length,
        waiting: _waiters.length,
        created: _created,
        destroyed: _destroyed,
        timeouts: _timeouts,
        validationFailures: _validationFailures,
      );

  /// Checks out a connection.
  ///
  /// Reuses an idle connection when one exists, creates a new one when
  /// under [PoolOptions.maxConnections], otherwise waits for a [release].
  Future<C> acquire() async {
    if (_closed) throw StateError('Pool is closed');

    final idle = await _takeIdle();
    if (idle != null) {
      if (_closed) {
        _inUse.remove(idle.conn);
        await _destroyEntry(idle);
        throw StateError('Pool is closed');
      }
      return idle.conn;
    }

    if (_total < options.maxConnections) {
      final _PooledEntry<C> entry;
      try {
        entry = await _createEntry();
      } catch (_) {
        _replenishForWaiters();
        rethrow;
      }
      if (_closed) {
        await _destroyEntry(entry);
        throw StateError('Pool is closed');
      }
      _inUse[entry.conn] = entry;
      return entry.conn;
    }

    return _waitForConnection();
  }

  /// Returns a connection obtained from [acquire].
  ///
  /// With `discard: true` the connection is destroyed instead of being
  /// reused. A waiting acquirer, if any, receives the connection directly.
  Future<void> release(C conn, {bool discard = false}) async {
    final entry = _inUse.remove(conn);
    if (entry == null) {
      throw StateError('Connection is not checked out from this pool');
    }
    if (discard || _closed) {
      await _destroyEntry(entry);
      _replenishForWaiters();
      return;
    }
    entry.lastUsedAt = _now();
    _handOff(entry);
  }

  /// How often the background eviction timer runs for [options]:
  /// half of the smallest enabled duration among `idleTimeout` and
  /// `maxLifetime`, or `null` when both are disabled.
  static Duration? evictionIntervalFor(PoolOptions options) {
    final enabled = [options.idleTimeout, options.maxLifetime]
        .where((d) => d > Duration.zero)
        .toList();
    if (enabled.isEmpty) return null;
    final smallest = enabled.reduce((a, b) => a < b ? a : b);
    final half = smallest ~/ 2;
    final interval = half > Duration.zero ? half : smallest;
    // Timer.periodic with a sub-millisecond period would spin the event loop.
    return interval < const Duration(milliseconds: 1)
        ? const Duration(milliseconds: 1)
        : interval;
  }

  /// Destroys idle connections that exceeded [PoolOptions.idleTimeout] or
  /// [PoolOptions.maxLifetime]. Called periodically by the pool; exposed so
  /// callers and tests can trigger it directly.
  Future<void> evictExpired() async {
    if (_closed) return;
    final expired = _idle
        .where((e) => _isPastLifetime(e) || _isIdleExpired(e))
        .toList();
    for (final entry in expired) {
      _idle.remove(entry);
    }
    for (final entry in expired) {
      await _destroyEntry(entry);
    }
  }

  /// Closes the pool: destroys idle connections and fails every waiter.
  /// Connections still checked out are destroyed when released.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _evictionTimer?.cancel();
    while (_waiters.isNotEmpty) {
      _waiters.removeFirst().completeError(StateError('Pool is closed'));
    }
    final idle = List<_PooledEntry<C>>.of(_idle);
    _idle.clear();
    for (final entry in idle) {
      await _destroyEntry(entry);
    }
  }

  // ---- internals -------------------------------------------------------

  /// Pops idle entries (LIFO) until one is usable. Returns null when none.
  ///
  /// The popped entry is registered as in-use before any await so that
  /// [_total] stays accurate while it is being validated.
  Future<_PooledEntry<C>?> _takeIdle() async {
    while (_idle.isNotEmpty) {
      final entry = _idle.removeLast();
      _inUse[entry.conn] = entry;

      if (_isPastLifetime(entry)) {
        _inUse.remove(entry.conn);
        await _destroyEntry(entry);
        continue;
      }
      if (_needsValidation(entry) && !await _isValid(entry)) {
        _validationFailures++;
        _inUse.remove(entry.conn);
        await _destroyEntry(entry);
        continue;
      }
      return entry;
    }
    return null;
  }

  bool _isPastLifetime(_PooledEntry<C> entry) =>
      options.maxLifetime > Duration.zero &&
      _now().difference(entry.createdAt) >= options.maxLifetime;

  bool _needsValidation(_PooledEntry<C> entry) =>
      _now().difference(entry.lastUsedAt) >= options.validationInterval;

  bool _isIdleExpired(_PooledEntry<C> entry) =>
      options.idleTimeout > Duration.zero &&
      _now().difference(entry.lastUsedAt) >= options.idleTimeout;

  /// Runs [validate]; a validator that throws, or that does not answer
  /// within [PoolOptions.acquireTimeout], counts as a failed validation.
  ///
  /// A hung validate may still complete later; that is harmless because the
  /// entry is destroyed either way and `destroy` closes its socket.
  Future<bool> _isValid(_PooledEntry<C> entry) async {
    try {
      return await validate(entry.conn).timeout(options.acquireTimeout);
    } catch (_) {
      return false;
    }
  }

  Future<_PooledEntry<C>> _createEntry() async {
    _pending++;
    try {
      final creating = create();
      final C conn;
      try {
        conn = await creating.timeout(options.acquireTimeout);
      } on TimeoutException {
        // The create may still land later; make sure it does not leak.
        unawaited(creating.then(
          (late) => destroy(late).catchError((_) {}),
          onError: (Object _, StackTrace _) {},
        ));
        _timeouts++;
        throw PoolTimeoutException(options.acquireTimeout, stats);
      }
      _created++;
      return _PooledEntry(conn, _now());
    } finally {
      _pending--;
    }
  }

  Future<void> _destroyEntry(_PooledEntry<C> entry) async {
    _destroyed++;
    try {
      await destroy(entry.conn);
    } catch (_) {
      // A connection we are throwing away anyway; nothing useful to do.
    }
  }

  /// Gives [entry] to the first waiter, or parks it as idle.
  void _handOff(_PooledEntry<C> entry) {
    if (_waiters.isNotEmpty) {
      _inUse[entry.conn] = entry;
      _waiters.removeFirst().complete(entry.conn);
      return;
    }
    _idle.add(entry);
  }

  /// After a connection was destroyed, opens replacements for waiters
  /// (bounded by maxConnections). Runs in the background.
  void _replenishForWaiters() {
    while (!_closed &&
        _waiters.length > _pendingForWaiters &&
        _total < options.maxConnections) {
      // _createEntry increments _pending synchronously, so the loop
      // terminates.
      _pendingForWaiters++;
      _createEntry().then(
        (entry) {
          _pendingForWaiters--;
          if (_closed) {
            unawaited(_destroyEntry(entry));
            return;
          }
          _handOff(entry);
        },
        onError: (Object error, StackTrace stackTrace) {
          _pendingForWaiters--;
          if (_waiters.isNotEmpty) {
            _waiters.removeFirst().completeError(error, stackTrace);
          }
        },
      );
    }
  }

  Future<C> _waitForConnection() async {
    final completer = Completer<C>();
    _waiters.add(completer);
    try {
      return await completer.future.timeout(options.acquireTimeout);
    } on TimeoutException {
      // The timer fired before any release reached us. Nothing can have
      // completed the completer in between (release runs in its own
      // microtask chain), so it is safe to drop it.
      _waiters.remove(completer);
      _timeouts++;
      throw PoolTimeoutException(options.acquireTimeout, stats);
    }
  }
}
