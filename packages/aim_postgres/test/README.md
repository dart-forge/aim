# aim_postgres テスト

このパッケージには、ユニットテストと統合テストの両方が含まれています。

## テスト構成

### ユニットテスト (`test/unit/`)

PostgreSQLサーバーを必要としない、低レベルのロジックテスト：

- `pg_connection_test.dart`: バイト変換、メッセージタイプ判定、QueryResult処理
- `pg_database_test.dart`: パラメータ変換ロジック（プレースホルダー）

### 統合テスト (`test/integration/`)

実際のPostgreSQLサーバーを使用した統合テスト。すべて `@Tags(['integration'])` が付いており、
`dart_test.yaml` の設定で**デフォルトではスキップされます**（Docker が要るため）。各ファイルの
`setUpAll` が `docker_stack.dart` のヘルパーを呼び、必要な Postgres コンテナを自分で起動してから
接続するので、事前に `docker compose` を手で叩く必要はありません。

- `pg_connection_integration_test.dart`: Simple QueryとExtended Queryプロトコル
- `pg_connection_md5_test.dart`: MD5認証
- `pg_connection_scram_test.dart`: SCRAM-SHA-256認証
- `pg_connection_notice_test.dart`: NoticeResponseの処理
- `pg_database_integration_test.dart`: 名前付き/位置パラメータ、CRUD操作
- `pg_database_transaction_test.dart`: トランザクション（コミット/ロールバック）
- `pg_pool_integration_test.dart`: コネクションプール
- `pg_typed_results_integration_test.dart`: 型付き結果のデコード

## テスト実行方法

### ユニットテストのみ実行（デフォルト）

```bash
cd packages/aim_postgres
dart test
```

Postgres サーバーは不要で、高速に実行できます。統合テストはこの実行ではスキップされ、
スキップ理由（Docker が必要であること）と実行コマンドがそのまま表示されます。

### 統合テストを実行

```bash
cd packages/aim_postgres
dart test -t integration --run-skipped
```

コンテナは各統合テストファイルの `setUpAll` が自動で起動します（`docker compose ... up -d
--wait` を実行するだけなので、既に起動済みで健全なら数秒で戻ってきます）。Docker が入っていない
環境でこれを実行すると、その旨を伝えるエラーで失敗します。

### 特定のテストファイルを実行

```bash
# ユニットテスト
dart test test/unit/pg_connection_test.dart

# 統合テスト
dart test -t integration --run-skipped test/integration/pg_connection_integration_test.dart
```

### 特定のテストケースを実行

```bash
dart test --name "SELECT with parameters"
```

## コンテナを止める

統合テストは複数のファイルが同じコンテナ群を並行して使うため、テスト側では**コンテナを止めません**
（1つのスイートの `tearDownAll` で止めると、並行して走っている他のスイートを壊してしまうため）。
使い終わったら手動で止めてください：

```bash
cd packages/aim_postgres
docker compose -f test/integration/docker-compose.yml down
```

## 前提条件

### ユニットテスト
- Dart SDK 3.13.0以上

### 統合テスト
- Dart SDK 3.13.0以上
- Docker & Docker Compose（`docker compose` サブコマンドが使えること）

## テストデータベース情報

統合テストでは以下の設定でPostgreSQLに接続します（詳細は
`test/integration/docker-compose.yml`）：

| サービス | ホストポート | 認証方式 |
| --- | --- | --- |
| postgres_password | 15433 | cleartext password |
| postgres_md5 | 15434 | md5 |
| postgres_scram | 15435 | scram-sha-256 |

いずれも `test_db` / `test` / `test`（データベース名・ユーザー・パスワード）です。ホストの
5432/5433番台は他のPostgreSQLやDBプロキシと衝突しがちなので、15000番台に寄せています。

## CI

これらの統合テストはCIでは実行されません（Dockerを必要とするため）。`dart analyze` と
ユニットテストだけがCI対象です。統合テストはローカルで上記の通り実行してください。

## トラブルシューティング

### ポートが既に使用されている

エラーメッセージに、どのポートが衝突しているか・どのコマンドで確認できるかが出ます
（`lsof -nP -iTCP:<port> -sTCP:LISTEN`）。該当ポートを使っている別プロセスを止めるか、
`test/integration/docker-compose.yml` の `ports` を編集して別のポートに変更してください。
その場合はテストコード内の接続文字列（`postgresql://test:test@localhost:<port>/test_db`）も
合わせて更新してください。

### PostgreSQLコンテナが起動しない

ログを確認：

```bash
docker logs aim_postgres_password_test   # または aim_postgres_md5_test / aim_postgres_scram_test
```

コンテナを強制削除して再起動：

```bash
docker rm -f aim_postgres_password_test aim_postgres_md5_test aim_postgres_scram_test
dart test -t integration --run-skipped
```

## テスト戦略の参考

このテスト戦略は、Dart `postgres`パッケージの実装を参考にしています：

- [isoos/postgresql-dart](https://github.com/isoos/postgresql-dart)
