import 'dart:typed_data';

import 'package:aim_mysql/src/exceptions.dart';
import 'package:aim_mysql/src/statement.dart';
import 'package:aim_mysql/src/types/column_type.dart';
import 'package:test/test.dart';

void main() {
  group('buildExecutePayload', () {
    // Header is always 9 bytes: int4 statement_id, int1 flags,
    // int4 iteration_count.
    const headerLength = 9;

    test("a parameter's NULL bit is bit i of the bitmap, not bit i + 2", () {
      // This is the row-side rule (see decodeBinaryRow) borrowed by
      // mistake. Parameter 0 alone already catches it: its bit would land
      // at bit 2 instead of bit 0.
      final statement = PreparedStatement(
        id: 1,
        parameterCount: 1,
        columns: const [],
      );

      final payload = buildExecutePayload(statement, [null]);

      expect(
        payload[headerLength],
        0x01,
        reason:
            'bit 0 set for parameter 0; the row-side +2 offset would set '
            'bit 2 instead (0x04)',
      );
    });

    test(
      'a mixed null/non-null pattern pins every bit position, not just 0',
      () {
        // Three parameters, alternating null: bits 0 and 2 set, bit 1 clear.
        // Applying the row rule's +2 offset instead would set bits 2 and 4,
        // clear bit 3 -- 0x14, not 0x05 -- so this is unambiguous either way.
        final statement = PreparedStatement(
          id: 1,
          parameterCount: 3,
          columns: const [],
        );

        final payload = buildExecutePayload(statement, [null, 5, null]);

        expect(payload[headerLength], 0x05);
      },
    );

    test("the bitmap's length is (parameterCount + 7) ~/ 8 bytes", () {
      // Checked by where new_params_bound_flag (always exactly 1) turns up
      // right after the bitmap, for parameter counts either side of every
      // byte boundary up to two bytes.
      for (final parameterCount in [1, 7, 8, 9, 16, 17]) {
        final statement = PreparedStatement(
          id: 1,
          parameterCount: parameterCount,
          columns: const [],
        );
        final values = List<Object?>.filled(parameterCount, 1);

        final payload = buildExecutePayload(statement, values);

        final bitmapLength = (parameterCount + 7) ~/ 8;
        expect(
          payload[headerLength + bitmapLength],
          1,
          reason:
              'new_params_bound_flag should sit right after a '
              '$bitmapLength-byte bitmap for $parameterCount parameter(s)',
        );
      }
    });

    test('new_params_bound_flag is 1', () {
      final statement = PreparedStatement(
        id: 1,
        parameterCount: 1,
        columns: const [],
      );

      final payload = buildExecutePayload(statement, [5]);

      expect(payload[headerLength + 1], 1);
    });

    test('one (type, unsigned flag) pair per parameter, in order', () {
      final statement = PreparedStatement(
        id: 1,
        parameterCount: 2,
        columns: const [],
      );

      final payload = buildExecutePayload(statement, [5, 'x']);

      // header + a 1-byte bitmap (2 parameters) + the bound flag.
      final typesStart = headerLength + 1 + 1;
      expect(
        payload[typesStart],
        ColumnType.longLong,
        reason: 'int -> LONGLONG',
      );
      expect(payload[typesStart + 1], 0x00, reason: 'signed');
      expect(
        payload[typesStart + 2],
        ColumnType.varString,
        reason: 'String -> VARSTRING',
      );
      expect(payload[typesStart + 3], 0x00, reason: 'signed');
    });

    test('value bytes appear only for non-NULL parameters, in order', () {
      final statement = PreparedStatement(
        id: 1,
        parameterCount: 2,
        columns: const [],
      );

      final payload = buildExecutePayload(statement, [null, 5]);

      // header + bitmap(1) + flag(1) + 2 type/sign pairs (4).
      final valuesStart = headerLength + 1 + 1 + 4;
      expect(
        payload.length,
        valuesStart + 8,
        reason: 'only one 8-byte LONGLONG value, for the non-NULL parameter',
      );
      expect(
        ByteData.sublistView(
          payload,
          valuesStart,
          valuesStart + 8,
        ).getInt64(0, Endian.little),
        5,
      );
    });

    test(
      'no parameters means no bitmap, flag, type bytes or values at all',
      () {
        final statement = PreparedStatement(
          id: 7,
          parameterCount: 0,
          columns: const [],
        );

        final payload = buildExecutePayload(statement, const []);

        expect(payload.length, headerLength);
      },
    );

    test(
      'the header is the statement id, then flags, then iteration_count',
      () {
        final statement = PreparedStatement(
          id: 0x01020304,
          parameterCount: 0,
          columns: const [],
        );

        final payload = buildExecutePayload(statement, const []);

        expect(payload.sublist(0, 4), [
          0x04,
          0x03,
          0x02,
          0x01,
        ], reason: 'id, LE');
        expect(payload[4], 0x00, reason: 'flags: no cursor');
        expect(payload.sublist(5, 9), [
          0x01,
          0x00,
          0x00,
          0x00,
        ], reason: 'iteration_count is always 1');
      },
    );
  });

  group('withReprepareRetry', () {
    MySqlException needReprepare() => MySqlException(
      errorCode: 1615,
      sqlState: 'HY000',
      message: 'statement needs to be re-prepared',
    );

    test('retries once on 1615 and succeeds', () async {
      var calls = 0;
      var invalidated = false;

      final result = await withReprepareRetry<int>(() async {
        calls++;
        if (calls == 1) throw needReprepare();
        return 42;
      }, () => invalidated = true);

      expect(result, 42);
      expect(calls, 2, reason: 'one failing attempt, one retry');
      expect(invalidated, isTrue);
    });

    test('a second 1615 propagates -- retries only once', () async {
      var calls = 0;

      await expectLater(
        withReprepareRetry<int>(() async {
          calls++;
          throw needReprepare();
        }, () {}),
        throwsA(isA<MySqlException>()),
      );

      // Not just that it threw: an implementation that retried a second
      // time would still succeed in the previous test, so the only way to
      // tell "retried once" from "retried until it gave up" is to count.
      expect(calls, 2, reason: 'no third attempt after the second failure');
    });

    test('any other error code does not retry at all', () async {
      var calls = 0;
      var invalidateCalled = false;

      await expectLater(
        withReprepareRetry<int>(() async {
          calls++;
          throw MySqlException(
            errorCode: 1062,
            sqlState: '23000',
            message: 'Duplicate entry',
          );
        }, () => invalidateCalled = true),
        throwsA(isA<MySqlException>()),
      );

      expect(calls, 1);
      expect(invalidateCalled, isFalse);
    });
  });

  group('MySqlResultSets aggregation', () {
    MySqlResult resultWith({int affectedRows = 0, int lastInsertId = 0}) =>
        MySqlResult(
          columns: const [],
          rows: const [],
          affectedRows: affectedRows,
          lastInsertId: lastInsertId,
          moreResults: false,
        );

    test(
      'lastInsertId is the last non-zero value, not simply the last set',
      () {
        // A later set that generated no id (0) must not overwrite an
        // earlier set's real one -- see MySqlResultSets.lastInsertId's doc
        // comment. Taking the last set plainly would answer 0 here.
        final sets = MySqlResultSets([
          resultWith(lastInsertId: 7),
          resultWith(lastInsertId: 0),
        ]);

        expect(sets.lastInsertId, 7);
      },
    );

    test('lastInsertId tracks the most recent non-zero id when several are non-zero', () {
      final sets = MySqlResultSets([
        resultWith(lastInsertId: 3),
        resultWith(lastInsertId: 9),
      ]);

      expect(sets.lastInsertId, 9);
    });

    test('lastInsertId is 0 when no set generated one', () {
      final sets = MySqlResultSets([resultWith(), resultWith()]);

      expect(sets.lastInsertId, 0);
    });

    test('totalAffectedRows adds every set together', () {
      final sets = MySqlResultSets([
        resultWith(affectedRows: 2),
        resultWith(affectedRows: 5),
      ]);

      expect(sets.totalAffectedRows, 7);
    });
  });
}
