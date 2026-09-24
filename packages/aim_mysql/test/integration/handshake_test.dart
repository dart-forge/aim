@Tags(['integration'])
library;

import 'package:aim_mysql/src/connection.dart';
import 'package:aim_mysql/src/exceptions.dart';
import 'package:rig_mysql/rig_mysql.dart';
import 'package:test/test.dart';

Future<MySqlConnection> open(String url) async =>
    MySqlConnection.connect(MySqlConnectionSettings.parse(url));

void main() {
  for (final version in ['8.4', '8.0']) {
    group('MySQL $version, caching_sha2_password', () {
      final lease = useMySql(version: version);

      test('connects over a plaintext socket', () async {
        final connection = await open(
          '${lease.url}?sslmode=disable&allowPublicKeyRetrieval=true',
        );
        addTearDown(connection.close);

        expect(connection.isOpen, isTrue);
        expect(await connection.ping(), isTrue);
      });

      test('connects over TLS, and the server agrees that it is TLS', () async {
        // The image generates a self-signed certificate, so require has to
        // not verify it.
        //
        // Ssl_cipher is the SERVER's accounting of the session, not this
        // driver's claim about it. Without reading it, "connects over TLS"
        // is satisfied by a connection that quietly stayed in plaintext —
        // these containers accept both, so success proves nothing about
        // which one happened.
        final connection = await open('${lease.url}?sslmode=require');
        addTearDown(connection.close);

        expect(await connection.ping(), isTrue);
        expect(
          await connection.fetchSingleValue("SHOW STATUS LIKE 'Ssl_cipher'"),
          isNotEmpty,
        );
      });

      test('and a plaintext connection is not, by the same measure', () async {
        // The other side of the same reading, so the assertion above is
        // known to distinguish the two rather than always holding.
        final connection = await open(
          '${lease.url}?sslmode=disable&allowPublicKeyRetrieval=true',
        );
        addTearDown(connection.close);

        expect(
          await connection.fetchSingleValue("SHOW STATUS LIKE 'Ssl_cipher'"),
          isEmpty,
        );
      });

      test('verify-full refuses the self-signed certificate', () async {
        // Which is how we know require is not verifying by accident and
        // verify-full is not a no-op. If this ever passes, one of the two
        // modes has stopped meaning anything.
        //
        // The type stays loose on purpose: this failure comes out of
        // dart:io's TLS stack, and wrapping it would hide which
        // certificate check actually refused.
        await expectLater(
          open('${lease.url}?sslmode=verify-full'),
          throwsA(isA<Exception>()),
        );
      });

      test('prefer takes the TLS the server offers', () async {
        // prefer is the DEFAULT, and it exists so that leaving sslmode out
        // of the URL does not quietly produce a plaintext connection. So
        // this is the one path where "it connected" is the least
        // interesting thing that could be asserted: a prefer arm that
        // ignored what the server offered and stayed plaintext would
        // connect and ping just as happily.
        final connection = await open('${lease.url}?sslmode=prefer');
        addTearDown(connection.close);

        expect(await connection.ping(), isTrue);
        expect(
          await connection.fetchSingleValue("SHOW STATUS LIKE 'Ssl_cipher'"),
          isNotEmpty,
          reason: 'prefer must not silently settle for plaintext',
        );
      });

      test('reads sql_mode off the session', () async {
        // Not to change it — to know where a string literal ends.
        final connection = await open(
          '${lease.url}?sslmode=disable&allowPublicKeyRetrieval=true',
        );
        addTearDown(connection.close);

        expect(
          connection.sqlMode,
          contains('STRICT_TRANS_TABLES'),
          reason: 'which is in the default sql_mode for both 8.0 and 8.4',
        );
      });

      test('the dialect follows NO_BACKSLASH_ESCAPES, both ways', () async {
        // Comparing the dialect against the session's own sql_mode reads
        // like a real check and is not one: the default mode never contains
        // NO_BACKSLASH_ESCAPES, so the comparison reduces to `true == !false`
        // and holds even against a getter that ignores sql_mode entirely.
        // The only way to test a branch is to reach it.
        //
        // Turning the mode on also exercises refreshSqlMode end to end,
        // which nothing else here does.
        final connection = await open(
          '${lease.url}?sslmode=disable&allowPublicKeyRetrieval=true',
        );
        addTearDown(connection.close);

        expect(
          connection.sqlMode,
          isNot(contains('NO_BACKSLASH_ESCAPES')),
          reason: 'the default mode, which is where we start',
        );
        expect(connection.dialect.backslashEscapes, isTrue);

        await connection.fetchSingleValue(
          "SET SESSION sql_mode = 'NO_BACKSLASH_ESCAPES'",
        );
        await connection.refreshSqlMode();

        expect(connection.sqlMode, contains('NO_BACKSLASH_ESCAPES'));
        expect(
          connection.dialect.backslashEscapes,
          isFalse,
          reason: 'the other branch, reached rather than inferred',
        );
      });

      test('a wrong password fails with access denied, not a hang', () async {
        final wrong = lease.url.replaceFirst(
          ':${Uri.encodeComponent(lease.password)}@',
          ':wrong@',
        );

        await expectLater(
          open('$wrong?sslmode=disable&allowPublicKeyRetrieval=true'),
          throwsA(isA<MySqlAccessDenied>()),
        );
      });

      test('a database that does not exist fails clearly', () async {
        final missing =
            '${lease.url.substring(0, lease.url.lastIndexOf('/'))}/no_such_db';

        await expectLater(
          open('$missing?sslmode=disable&allowPublicKeyRetrieval=true'),
          throwsA(isA<MySqlException>()),
        );
      });

      test(
        'a plaintext connection with a cold cache goes through RSA',
        () async {
          // The only path that exercises the public key, and the reason
          // rsa_oaep.dart exists. Flushing first is what makes the cache cold;
          // without it an earlier test in this group has already warmed it and
          // this would pass without encrypting anything.
          await lease.flushAuthCache();

          final connection = await open(
            '${lease.url}?sslmode=disable&allowPublicKeyRetrieval=true',
          );
          addTearDown(connection.close);

          expect(await connection.ping(), isTrue);
        },
      );

      test('and a warm cache then takes the fast path', () async {
        // The 0x03 branch. Running it right after the cold one is what
        // makes it the warm case rather than a second cold one.
        await lease.flushAuthCache();
        final first = await open(
          '${lease.url}?sslmode=disable&allowPublicKeyRetrieval=true',
        );
        await first.close();

        final second = await open(
          '${lease.url}?sslmode=disable&allowPublicKeyRetrieval=true',
        );
        addTearDown(second.close);

        expect(await second.ping(), isTrue);
      });

      test(
        'a TLS connection with a cold cache sends the password in the clear',
        () async {
          // Cleartext inside TLS: the other full-auth branch.
          await lease.flushAuthCache();

          final connection = await open('${lease.url}?sslmode=require');
          addTearDown(connection.close);

          expect(await connection.ping(), isTrue);
        },
      );

      test(
        'a closed connection says so instead of writing to a dead socket',
        () async {
          final connection = await open(
            '${lease.url}?sslmode=disable&allowPublicKeyRetrieval=true',
          );
          await connection.close();

          expect(connection.isOpen, isFalse);
          await expectLater(
            connection.ping(),
            throwsA(
              isA<StateError>().having(
                (e) => e.toString(),
                'toString',
                contains(mysqlClosedMessage),
              ),
            ),
          );
        },
      );
    });

    group('MySQL $version, mysql_native_password', () {
      // Otherwise the SHA-1 scramble never meets a server. 8.4 does not
      // load the plugin by default; rig_mysql turns it on for this auth
      // mode, which is the whole reason MySqlAuth exists.
      final lease = useMySql(version: version, auth: MySqlAuth.nativePassword);

      test('connects over a plaintext socket', () async {
        final connection = await open(
          '${lease.url}?sslmode=disable&allowPublicKeyRetrieval=true',
        );
        addTearDown(connection.close);

        expect(await connection.ping(), isTrue);
      });

      test('connects over TLS', () async {
        final connection = await open('${lease.url}?sslmode=require');
        addTearDown(connection.close);

        expect(await connection.ping(), isTrue);
      });

      test('a wrong password fails with access denied', () async {
        final wrong = lease.url.replaceFirst(
          ':${Uri.encodeComponent(lease.password)}@',
          ':wrong@',
        );

        await expectLater(
          open('$wrong?sslmode=disable&allowPublicKeyRetrieval=true'),
          throwsA(isA<MySqlAccessDenied>()),
        );
      });
    });
  }
}
