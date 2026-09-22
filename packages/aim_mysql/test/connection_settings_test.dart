import 'package:aim_mysql/src/connection.dart';
import 'package:test/test.dart';

void main() {
  group('parsing the URL', () {
    test('takes the host, port, user, password and database', () {
      final settings = MySqlConnectionSettings.parse(
        'mysql://alice:s3cret@db.example:3307/shop',
      );

      expect(settings.host, 'db.example');
      expect(settings.port, 3307);
      expect(settings.user, 'alice');
      expect(settings.password, 's3cret');
      expect(settings.database, 'shop');
    });

    test('defaults the port to 3306', () {
      expect(
        MySqlConnectionSettings.parse('mysql://alice@db.example/shop').port,
        3306,
      );
    });

    test(
      'an absent password is empty, which is a real MySQL account shape',
      () {
        expect(
          MySqlConnectionSettings.parse('mysql://alice@db.example/shop')
              .password,
          '',
        );
      },
    );

    test('an absent database is null, not the empty string', () {
      // Which is the difference between "connect to no database" and
      // "connect to a database whose name is empty" — the second is an
      // error the server would report.
      expect(
        MySqlConnectionSettings.parse('mysql://alice@db.example').database,
        isNull,
      );
      expect(
        MySqlConnectionSettings.parse('mysql://alice@db.example/').database,
        isNull,
      );
    });

    test('percent-encoded credentials are decoded', () {
      // A password with an @ or a / in it has to be encoded to survive the
      // URL, and has to be decoded before it is hashed.
      final settings = MySqlConnectionSettings.parse(
        'mysql://al%40ice:p%2Fss%40word@db.example/shop',
      );

      expect(settings.user, 'al@ice');
      expect(settings.password, 'p/ss@word');
    });

    test('a non-ASCII password survives the round trip', () {
      final settings = MySqlConnectionSettings.parse(
        'mysql://alice:${Uri.encodeComponent('パスワード')}@db.example/shop',
      );

      expect(settings.password, 'パスワード');
    });
  });

  group('sslmode', () {
    MySqlSslMode modeOf(String query) =>
        MySqlConnectionSettings.parse('mysql://alice@db.example/shop$query')
            .sslMode;

    test('defaults to prefer, not disable', () {
      // Leaving it out must not produce a plaintext connection to a
      // network database.
      expect(modeOf(''), MySqlSslMode.prefer);
    });

    test('reads each mode this driver accepts', () {
      expect(modeOf('?sslmode=disable'), MySqlSslMode.disable);
      expect(modeOf('?sslmode=prefer'), MySqlSslMode.prefer);
      expect(modeOf('?sslmode=require'), MySqlSslMode.require);
      expect(modeOf('?sslmode=verify-ca'), MySqlSslMode.verifyCa);
      expect(modeOf('?sslmode=verify-full'), MySqlSslMode.verifyFull);
    });

    test('is case-insensitive', () {
      expect(modeOf('?sslmode=REQUIRE'), MySqlSslMode.require);
    });

    test('rejects a mode it does not implement, naming it', () {
      // "allow" is in libpq's vocabulary and not in this driver's. Silently
      // treating it as prefer would hide a typo just as effectively.
      expect(
        () => modeOf('?sslmode=allow'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.toString(),
            'toString',
            contains('allow'),
          ),
        ),
      );
    });

    test('takes the CA file from sslrootcert', () {
      expect(
        MySqlConnectionSettings.parse(
          'mysql://alice@db.example/shop?sslmode=verify-ca&sslrootcert=/tmp/ca.pem',
        ).caFile,
        '/tmp/ca.pem',
      );
    });
  });

  group('rejecting what it cannot connect to', () {
    test('a scheme that is not mysql', () {
      expect(
        () => MySqlConnectionSettings.parse('postgresql://a@h/db'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('no host', () {
      expect(
        () => MySqlConnectionSettings.parse('mysql:///shop'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('no user', () {
      // MySQL has no equivalent of falling back to the OS user here.
      expect(
        () => MySqlConnectionSettings.parse('mysql://db.example/shop'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
