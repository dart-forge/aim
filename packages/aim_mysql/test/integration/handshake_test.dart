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
        final connection = await open('${lease.url}?sslmode=disable');
        addTearDown(connection.close);

        expect(connection.isOpen, isTrue);
        expect(await connection.ping(), isTrue);
      });

      test('connects over TLS', () async {
        // The image generates a self-signed certificate, so require has to
        // not verify it. That it connects at all is the point.
        final connection = await open('${lease.url}?sslmode=require');
        addTearDown(connection.close);

        expect(await connection.ping(), isTrue);
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

      test('prefer reaches the server that offers TLS', () async {
        final connection = await open('${lease.url}?sslmode=prefer');
        addTearDown(connection.close);

        expect(await connection.ping(), isTrue);
      });

      test('reads sql_mode off the session', () async {
        // Not to change it — to know where a string literal ends.
        final connection = await open('${lease.url}?sslmode=disable');
        addTearDown(connection.close);

        expect(
          connection.sqlMode,
          contains('STRICT_TRANS_TABLES'),
          reason: 'which is in the default sql_mode for both 8.0 and 8.4',
        );
      });

      test('the dialect follows NO_BACKSLASH_ESCAPES', () async {
        final connection = await open('${lease.url}?sslmode=disable');
        addTearDown(connection.close);

        expect(
          connection.dialect.backslashEscapes,
          !connection.sqlMode.contains('NO_BACKSLASH_ESCAPES'),
        );
      });

      test('a wrong password fails with access denied, not a hang', () async {
        final wrong = lease.url.replaceFirst(
          ':${Uri.encodeComponent(lease.password)}@',
          ':wrong@',
        );

        await expectLater(
          open('$wrong?sslmode=disable'),
          throwsA(isA<MySqlAccessDenied>()),
        );
      });

      test('a database that does not exist fails clearly', () async {
        final missing =
            '${lease.url.substring(0, lease.url.lastIndexOf('/'))}/no_such_db';

        await expectLater(
          open('$missing?sslmode=disable'),
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

          final connection = await open('${lease.url}?sslmode=disable');
          addTearDown(connection.close);

          expect(await connection.ping(), isTrue);
        },
      );

      test('and a warm cache then takes the fast path', () async {
        // The 0x03 branch. Running it right after the cold one is what
        // makes it the warm case rather than a second cold one.
        await lease.flushAuthCache();
        final first = await open('${lease.url}?sslmode=disable');
        await first.close();

        final second = await open('${lease.url}?sslmode=disable');
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
          final connection = await open('${lease.url}?sslmode=disable');
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
        final connection = await open('${lease.url}?sslmode=disable');
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
          open('$wrong?sslmode=disable'),
          throwsA(isA<MySqlAccessDenied>()),
        );
      });
    });
  }
}
