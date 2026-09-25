import 'dart:typed_data';

import 'package:aim_mysql/src/exceptions.dart';
import 'package:aim_mysql/src/protocol/packets.dart';
import 'package:test/test.dart';

import 'protocol/handshake_fixtures.dart';

ErrPacket errno(int code, {String sqlState = 'HY000', String message = 'x'}) =>
    ErrPacket(errorCode: code, sqlState: sqlState, message: message);

void main() {
  group('classifying by errno', () {
    test('1062 is a unique violation', () {
      expect(mysqlErrorFor(errno(1062)), isA<MySqlUniqueViolation>());
    });

    test('1048 is a NOT NULL violation', () {
      expect(mysqlErrorFor(errno(1048)), isA<MySqlNotNullViolation>());
    });

    test('all four foreign-key errnos map to one type', () {
      // InnoDB reports 1451 and 1452; the generic pair still exists and
      // means the same thing to a caller.
      for (final code in [1216, 1217, 1451, 1452]) {
        expect(
          mysqlErrorFor(errno(code)),
          isA<MySqlForeignKeyViolation>(),
          reason: 'errno $code',
        );
      }
    });

    test('3819 is a check violation', () {
      expect(mysqlErrorFor(errno(3819)), isA<MySqlCheckViolation>());
    });

    test('1213 is a deadlock and 1205 is a lock wait timeout', () {
      // Different types because the right response differs: a deadlock is
      // safe to retry immediately, a lock timeout usually is not.
      expect(mysqlErrorFor(errno(1213)), isA<MySqlDeadlock>());
      expect(mysqlErrorFor(errno(1205)), isA<MySqlLockWaitTimeout>());
    });

    test('the three access-denied errnos map to one type', () {
      for (final code in [1044, 1045, 1698]) {
        expect(
          mysqlErrorFor(errno(code)),
          isA<MySqlAccessDenied>(),
          reason: 'errno $code',
        );
      }
    });

    test('anything unclassified is still a MySqlException', () {
      // Not swallowed and not turned into something vaguer: the caller can
      // read errno off it and branch itself.
      final error = mysqlErrorFor(errno(1146, message: 'No such table'));

      expect(error, isA<MySqlException>());
      expect(error.errorCode, 1146);
      expect(error.message, 'No such table');
    });

    test('every classified type is also a MySqlException', () {
      // So a caller that only wants "the database said no" catches one
      // thing.
      for (final code in [1062, 1048, 1451, 3819, 1213, 1205, 1045]) {
        expect(
          mysqlErrorFor(errno(code)),
          isA<MySqlException>(),
          reason: 'errno $code',
        );
      }
    });

    test('carries the SQL state through', () {
      expect(mysqlErrorFor(errno(1062, sqlState: '23000')).sqlState, '23000');
    });

    test('carries the statement when one was given', () {
      final error = mysqlErrorFor(errno(1062), sql: 'INSERT INTO t VALUES (?)');

      expect(error.sql, 'INSERT INTO t VALUES (?)');
      expect(error.toString(), contains('INSERT INTO t'));
    });

    test('says the errno and the message when there is no statement', () {
      final text = mysqlErrorFor(errno(1213, message: 'Deadlock found'))
          .toString();

      expect(text, contains('1213'));
      expect(text, contains('Deadlock found'));
    });

    test('a real wrong-password ERR from a live server is access denied', () {
      // errWrongPassword is captured bytes (tool/capture_handshake.dart),
      // not one assembled by hand -- proof that this classification meets
      // what a real server actually sends for errno 1045, not just what
      // errno() above constructs for it.
      final err = parseAuthPhasePacket(
        Uint8List.fromList(errWrongPassword),
      ) as ErrPacket;

      expect(mysqlErrorFor(err), isA<MySqlAccessDenied>());
    });
  });

  test('there is one wording for a call on a closed database', () {
    // Which check fails depends only on how far the call had got when close
    // came, and a caller can act on neither difference.
    //
    // mysqlClosedMessage is a plain constant, thrown as
    // `StateError(mysqlClosedMessage)` at the call site -- the same shape
    // aim_sqlite uses for the same purpose -- rather than a dedicated
    // exception type.
    expect(mysqlClosedMessage, isNotEmpty);
    expect(
      StateError(mysqlClosedMessage).toString(),
      contains(mysqlClosedMessage),
    );
  });
}
