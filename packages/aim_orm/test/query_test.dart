// aim_orm's query_builder/query.dart does not itself build SELECT/WHERE/
// LIMIT SQL - that is generated per-table by aim_orm_codegen. What lives
// here is QueryFuture/FutureMixin: the plumbing that lets a generated
// builder be awaited directly instead of requiring an explicit .execute()
// call, as documented in docs/database/orm/select.md ("Await Directly").
// These tests exercise that delegation.
import 'dart:async';

import 'package:aim_orm/aim_orm.dart';
import 'package:test/test.dart';

class _FakeQuery<T> extends QueryFuture<T> with FutureMixin<T> {
  final Future<T> Function() _run;
  int executeCallCount = 0;

  _FakeQuery(this._run);

  @override
  Future<T> execute() {
    executeCallCount++;
    return _run();
  }
}

void main() {
  group('FutureMixin.then()', () {
    test('delegates to execute() and returns its result', () async {
      final query = _FakeQuery<int>(() async => 42);
      final result = await query.then((value) => value);
      expect(result, equals(42));
      expect(query.executeCallCount, equals(1));
    });

    test('each call to then() re-invokes execute()', () async {
      final query = _FakeQuery<int>(() async => 42);
      await query.then((value) => value);
      await query.then((value) => value);
      expect(query.executeCallCount, equals(2));
    });

    test(
      'the onValue callback receives the value execute() resolved with',
      () async {
        final query = _FakeQuery<String>(() async => 'row');
        final mapped = await query.then((value) => '$value!');
        expect(mapped, equals('row!'));
      },
    );

    test('onError is invoked when execute() throws', () async {
      final query = _FakeQuery<int>(() => Future.error(StateError('boom')));
      Object? caught;
      await query.then(
        (value) => value,
        onError: (Object error) {
          caught = error;
          return -1;
        },
      );
      expect(caught, isA<StateError>());
    });

    test('awaiting the query directly also goes through execute()', () async {
      final query = _FakeQuery<int>(() async => 7);
      final result = await query;
      expect(result, equals(7));
      expect(query.executeCallCount, equals(1));
    });
  });

  group('FutureMixin.catchError()', () {
    test('recovers from an error raised by execute()', () async {
      final query = _FakeQuery<int>(() => Future.error(StateError('boom')));
      final result = await query.catchError((Object _) => -1);
      expect(result, equals(-1));
    });

    test(
      'the test predicate still lets non-matching errors propagate',
      () async {
        final query = _FakeQuery<int>(
          () => Future.error(ArgumentError('nope')),
        );
        await expectLater(
          query.catchError(
            (Object _) => -1,
            test: (Object error) => error is StateError,
          ),
          throwsArgumentError,
        );
      },
    );
  });

  group('FutureMixin.timeout()', () {
    test('times out based on execute()\'s future, not a fixed delay', () async {
      final query = _FakeQuery<int>(
        () => Future<int>.delayed(const Duration(milliseconds: 50), () => 1),
      );
      await expectLater(
        query.timeout(const Duration(milliseconds: 5)),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('onTimeout supplies a fallback value instead of throwing', () async {
      final query = _FakeQuery<int>(
        () => Future<int>.delayed(const Duration(milliseconds: 50), () => 1),
      );
      final result = await query.timeout(
        const Duration(milliseconds: 5),
        onTimeout: () => -1,
      );
      expect(result, equals(-1));
    });
  });

  group('FutureMixin.whenComplete()', () {
    test('runs the callback after execute() resolves', () async {
      final query = _FakeQuery<int>(() async => 1);
      var ran = false;
      await query.whenComplete(() => ran = true);
      expect(ran, isTrue);
    });

    test(
      'runs the callback even when execute() throws, then rethrows',
      () async {
        final query = _FakeQuery<int>(() => Future.error(StateError('boom')));
        var ran = false;
        await expectLater(
          query.whenComplete(() => ran = true),
          throwsStateError,
        );
        expect(ran, isTrue);
      },
    );
  });

  group('FutureMixin.asStream()', () {
    test('emits the single value execute() resolved with', () async {
      final query = _FakeQuery<int>(() async => 9);
      final values = await query.asStream().toList();
      expect(values, equals([9]));
    });

    test('emits an error when execute() throws', () async {
      final query = _FakeQuery<int>(() => Future.error(StateError('boom')));
      await expectLater(query.asStream(), emitsError(isA<StateError>()));
    });
  });
}
