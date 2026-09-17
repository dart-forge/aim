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
先頭で `usePostgres()`（`package:rig_postgres`）を宣言すると、rig がコンテナを自分で用意して
くれるので、事前に何かを手で起動する必要はありません。ポートは**動的に割り当てられる**ので、
他のサービスと衝突しません。同じ認証設定を要求するスイートは1つのコンテナを共有し、その上で
**スイート毎に専用のデータベース**が切られるため、並行して走っても互いのテーブルを見ません。

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

コンテナは各統合テストファイルの `usePostgres()` が自動で用意します。同じ設定のコンテナが
既に起動済みで健全なら、それを再利用するだけなので数秒で戻ってきます。Docker が入っていない
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

統合テストが起動したコンテナは、テストが終わっても**意図的に落としません**（次回の実行が
コンテナの再利用で速くなるため）。溜まったコンテナは `rig prune` で削除できます：

```bash
rig prune
```

## 前提条件

### ユニットテスト
- Dart SDK 3.13.0以上

### 統合テスト
- Dart SDK 3.13.0以上
- Docker（コンテナは rig が直接起動します）

## テストデータベース情報

統合テストは `usePostgres()` の引数（`auth:`）で認証方式を選びます：

| ファイル | 認証方式 |
| --- | --- |
| `pg_connection_md5_test.dart` | md5 |
| `pg_connection_scram_test.dart` | scram-sha-256 |
| それ以外 | cleartext password（デフォルト） |

いずれも `test_db` / `test` / `test`（データベース名・ユーザー・パスワード）です。ホストポートは
rig が起動時に空いているものを割り当てるので、固定値はありません。

## CI

これらの統合テストはCIでは実行されません（Dockerを必要とするため）。`dart analyze` と
ユニットテストだけがCI対象です。統合テストはローカルで上記の通り実行してください。

## トラブルシューティング

### PostgreSQLコンテナが起動しない

`docker ps -a` でコンテナ名を確認し（rig が付けるランダムな名前です）、`docker logs <name>`
でログを確認してください。それでも解決しない場合は、`rig prune` で溜まったコンテナを一旦
全部消してから再実行してください：

```bash
rig prune
dart test -t integration --run-skipped
```

## テスト戦略の参考

このテスト戦略は、Dart `postgres`パッケージの実装を参考にしています：

- [isoos/postgresql-dart](https://github.com/isoos/postgresql-dart)
