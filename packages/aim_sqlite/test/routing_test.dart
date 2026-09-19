import 'package:aim_sqlite/src/routing.dart';
import 'package:test/test.dart';

void main() {
  test('sends plain reads to a reader', () {
    expect(routeFor('SELECT 1'), SqliteRoute.reader);
    expect(routeFor('select * from users'), SqliteRoute.reader);
    expect(
      routeFor('WITH t AS (SELECT 1) SELECT * FROM t'),
      SqliteRoute.reader,
    );
    expect(routeFor('EXPLAIN QUERY PLAN SELECT 1'), SqliteRoute.reader);
  });

  test('sends everything else to the writer', () {
    expect(routeFor('INSERT INTO t VALUES (1)'), SqliteRoute.writer);
    // Lower case on this path too, not only on the read path: the keyword
    // is upper cased before it is matched, and a write that fell through
    // this test because of its spelling would land on a reader.
    expect(routeFor('insert into t values (1)'), SqliteRoute.writer);
    expect(routeFor('UPDATE t SET a = 1'), SqliteRoute.writer);
    expect(routeFor('DELETE FROM t'), SqliteRoute.writer);
    expect(routeFor('CREATE TABLE t (a)'), SqliteRoute.writer);
    expect(routeFor('DROP TABLE t'), SqliteRoute.writer);
    expect(routeFor('REPLACE INTO t VALUES (1)'), SqliteRoute.writer);
    expect(routeFor('VACUUM'), SqliteRoute.writer);
  });

  test('sends transaction control to the writer', () {
    // sqlite3_stmt_readonly() says true for these, so the second stage of the
    // check cannot catch them. This stage is what keeps them off a reader.
    expect(routeFor('BEGIN'), SqliteRoute.writer);
    expect(routeFor('BEGIN IMMEDIATE'), SqliteRoute.writer);
    expect(routeFor('COMMIT'), SqliteRoute.writer);
    expect(routeFor('ROLLBACK'), SqliteRoute.writer);
    expect(routeFor('SAVEPOINT s'), SqliteRoute.writer);
    expect(routeFor('RELEASE s'), SqliteRoute.writer);
    expect(routeFor('ATTACH DATABASE ? AS other'), SqliteRoute.writer);
    expect(routeFor('DETACH other'), SqliteRoute.writer);
  });

  test(
    'sends every pragma to the writer, including the ones that only read',
    () {
      // Some pragmas read and some write. Guessing wrong in the safe direction
      // costs a slot on the writer; guessing wrong the other way is a failure.
      expect(routeFor('PRAGMA user_version'), SqliteRoute.writer);
      expect(routeFor('PRAGMA journal_mode = WAL'), SqliteRoute.writer);
    },
  );

  test('skips leading whitespace and comments', () {
    expect(routeFor('  \n\t SELECT 1'), SqliteRoute.reader);
    expect(routeFor('-- a comment\nSELECT 1'), SqliteRoute.reader);
    expect(routeFor('/* a comment */ SELECT 1'), SqliteRoute.reader);
    expect(
      routeFor('/* one */ -- two\n /* three */SELECT 1'),
      SqliteRoute.reader,
    );
    expect(
      routeFor('-- a comment\nINSERT INTO t VALUES (1)'),
      SqliteRoute.writer,
    );
  });

  test('sends an empty or comment-only statement to the writer', () {
    // Nothing to run, so nothing is at stake; keep it off the readers.
    expect(routeFor(''), SqliteRoute.writer);
    expect(routeFor('   '), SqliteRoute.writer);
    expect(routeFor('-- nothing here'), SqliteRoute.writer);
    // Both unterminated comments, not just the -- one: a /* with no */ has
    // its own branch, which gives up the same way. The second spelling is
    // the one that discriminates -- an implementation that stepped past an
    // unterminated /* instead of giving up would read the SELECT behind it
    // and send this to a reader.
    expect(routeFor('/* nothing here'), SqliteRoute.writer);
    expect(routeFor('/* SELECT 1'), SqliteRoute.writer);
  });

  test('routes by the first statement only', () {
    // 'SELECT 1; INSERT ...' comes here as a read. The reader isolate catches
    // it before running anything, because it prepares every statement and
    // checks sqlite3_stmt_readonly on all of them first.
    expect(routeFor('SELECT 1; INSERT INTO t VALUES (1)'), SqliteRoute.reader);
  });
}
