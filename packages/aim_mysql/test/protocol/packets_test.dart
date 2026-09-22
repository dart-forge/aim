import 'dart:typed_data';

import 'package:aim_mysql/src/exceptions.dart';
import 'package:aim_mysql/src/protocol/packets.dart';
import 'package:test/test.dart';

/// An OK packet body: no rows affected, no insert id, the given status.
Uint8List ok({int status = 0x0002, int warnings = 0, String info = ''}) =>
    Uint8List.fromList([
      0x00,
      0x00, // affected_rows, lenenc 0
      0x00, // last_insert_id, lenenc 0
      status & 0xff, status >> 8,
      warnings & 0xff, warnings >> 8,
      ...info.codeUnits,
    ]);

void main() {
  group('OK', () {
    test('carries the affected rows and the insert id', () {
      final payload = Uint8List.fromList([
        0x00,
        0x03, //       affected_rows = 3
        0xfc, 0x10, 0x27, // last_insert_id = 10000, lenenc 2-byte form
        0x02, 0x00, //  status_flags
        0x00, 0x00, //  warnings
      ]);

      final packet = parseCommandPacket(payload) as OkPacket;

      expect(packet.affectedRows, 3);
      expect(packet.lastInsertId, 10000);
    });

    test(
      'carries the status flags, which say whether a transaction is open',
      () {
        // The driver reads this to notice MySQL committing implicitly on DDL.
        final inTransaction =
            parseCommandPacket(ok(status: 0x0001)) as OkPacket;
        final notInTransaction = parseCommandPacket(ok()) as OkPacket;

        expect(inTransaction.inTransaction, isTrue);
        expect(notInTransaction.inTransaction, isFalse);
      },
    );

    test('carries the warning count', () {
      final packet = parseCommandPacket(ok(warnings: 7)) as OkPacket;

      expect(packet.warnings, 7);
    });

    test('keeps whatever info string follows', () {
      final packet =
          parseCommandPacket(ok(info: 'Rows matched: 1')) as OkPacket;

      expect(packet.info, 'Rows matched: 1');
    });

    test('an absent info string is empty, not null', () {
      expect((parseCommandPacket(ok()) as OkPacket).info, '');
    });

    test('a 0xfe header with a short payload is an OK, not an EOF', () {
      // This is how a result set ends once CLIENT_DEPRECATE_EOF is asked
      // for, and reading it as an EOF would lose the status flags.
      final payload = Uint8List.fromList([
        0xfe,
        0x00, 0x00, //  affected_rows, last_insert_id
        0x02, 0x00, //  status_flags
        0x00, 0x00, //  warnings
      ]);

      expect(parseCommandPacket(payload), isA<OkPacket>());
    });
  });

  group('ERR', () {
    Uint8List err(int code, String sqlState, String message) =>
        Uint8List.fromList([
          0xff,
          code & 0xff, code >> 8,
          0x23, // '#'
          ...sqlState.codeUnits,
          ...message.codeUnits,
        ]);

    test('carries the code, the SQL state and the message', () {
      final packet = parseCommandPacket(
        err(1062, '23000', "Duplicate entry 'a'"),
      ) as ErrPacket;

      expect(packet.errorCode, 1062);
      expect(packet.sqlState, '23000');
      expect(packet.message, "Duplicate entry 'a'");
    });

    test('reads a code above 255, which needs both bytes', () {
      // 3819 is the check-constraint error. A parser that reads one byte
      // gets 235 and classifies it as something else entirely.
      final packet =
          parseCommandPacket(err(3819, 'HY000', 'Check failed')) as ErrPacket;

      expect(packet.errorCode, 3819);
    });

    test('is recognised during the auth phase too', () {
      expect(
        parseAuthPhasePacket(err(1045, '28000', 'Access denied')),
        isA<ErrPacket>(),
      );
    });

    test('an empty message is allowed', () {
      expect(
        (parseCommandPacket(err(1064, '42000', '')) as ErrPacket).message,
        '',
      );
    });
  });

  group('the auth phase', () {
    test('0xfe is a request to switch plugin, with a new scramble', () {
      final payload = Uint8List.fromList([
        0xfe,
        ...'caching_sha2_password'.codeUnits,
        0x00,
        ...List.filled(20, 0x41),
        0x00,
      ]);

      final packet = parseAuthPhasePacket(payload) as AuthSwitchRequest;

      expect(packet.pluginName, 'caching_sha2_password');
      expect(packet.scramble, hasLength(20));
    });

    test('the scramble loses its trailing NUL', () {
      // The server appends one. Feeding 21 bytes to the scramble produces a
      // token of the right length that the server refuses.
      final payload = Uint8List.fromList([
        0xfe,
        ...'mysql_native_password'.codeUnits,
        0x00,
        ...List.filled(20, 0x41),
        0x00,
      ]);

      final packet = parseAuthPhasePacket(payload) as AuthSwitchRequest;

      expect(packet.scramble, everyElement(0x41));
      expect(packet.scramble, hasLength(20));
    });

    test('0x01 is more data, handed over as-is', () {
      // What it means depends on the plugin: 0x03 and 0x04 for
      // caching_sha2, a PEM public key later in the same exchange.
      final payload = Uint8List.fromList([0x01, 0x03]);

      final packet = parseAuthPhasePacket(payload) as AuthMoreData;

      expect(packet.data, [0x03]);
    });

    test('0x00 is a successful login', () {
      expect(parseAuthPhasePacket(ok()), isA<OkPacket>());
    });

    test('anything else during auth is a protocol failure', () {
      expect(
        () => parseAuthPhasePacket(Uint8List.fromList([0x42])),
        throwsA(isA<MySqlProtocolException>()),
      );
    });
  });

  group('a command that returns rows', () {
    test('opens with the column count', () {
      final packet =
          parseCommandPacket(Uint8List.fromList([0x03])) as ResultSetHeader;

      expect(packet.columnCount, 3);
    });

    test('reads a column count above 250, which is length-encoded', () {
      final packet = parseCommandPacket(
        Uint8List.fromList([0xfc, 0x2c, 0x01]),
      ) as ResultSetHeader;

      expect(packet.columnCount, 300);
    });

    test('a LOCAL INFILE request is a protocol failure', () {
      // This driver does not ask for CLIENT_LOCAL_FILES, so the server has
      // no business asking for a file. Getting one means something earlier
      // was misread.
      expect(
        () => parseCommandPacket(Uint8List.fromList([0xfb, ...'x'.codeUnits])),
        throwsA(isA<MySqlProtocolException>()),
      );
    });

    test('an empty payload is a protocol failure, not an empty OK', () {
      expect(
        () => parseCommandPacket(Uint8List(0)),
        throwsA(isA<MySqlProtocolException>()),
      );
    });
  });

  group('EOF', () {
    test('is read when one turns up, for the status flags', () {
      // With CLIENT_DEPRECATE_EOF the server should not send these, so one
      // arriving is worth being able to read rather than crashing on.
      //
      // Status 0x0001 is SERVER_STATUS_IN_TRANS alone: EOF_Packet orders
      // its fields as warnings then status_flags (the reverse of
      // OK_Packet), so the third byte here is the low byte of
      // status_flags, not of warnings.
      final payload = Uint8List.fromList([0xfe, 0x00, 0x00, 0x01, 0x00]);

      final packet = parseEofPacket(payload);

      expect(packet.warnings, 0);
      expect(packet.inTransaction, isTrue);
    });
  });
}
