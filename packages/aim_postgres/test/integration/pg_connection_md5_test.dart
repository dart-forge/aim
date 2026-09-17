@Tags(['integration'])
library;

import 'package:aim_postgres/aim_postgres.dart';
import 'package:rig_postgres/rig_postgres.dart';
import 'package:test/test.dart';

void main() {
  final pg = usePostgres(auth: PgAuth.md5);

  group('MD5 Authentication', () {
    test('connects with MD5 auth', () async {
      final conn = await PostgresConnection.connect(pg.url);

      // クエリを実行して認証成功を確認
      final result = await conn.sendSimpleQuery('SELECT 1');
      expect(result.rows.length, 1);

      await conn.close();
    });

    test('fails with wrong password', () async {
      expect(
        () => PostgresConnection.connect(
          'postgresql://test:wrong@${pg.host}:${pg.port}/${pg.database}',
        ),
        throwsA(isA<QueryException>()),
      );
    });

    test('sends Terminate message on close', () async {
      final conn = await PostgresConnection.connect(pg.url);

      // Execute a query to ensure connection is ready
      final result = await conn.sendSimpleQuery('SELECT 1');
      expect(result.rows.length, 1);

      // Close should send Terminate message and complete successfully
      await expectLater(conn.close(), completes);
    });
  });
}
