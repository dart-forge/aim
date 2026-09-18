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
くれるので、事前に何かを手で起動する必要はありません。ポートは**コンテナを作るときに
空いているものが割り当てられ、そのコンテナを使い回す間は同じポートを使い続けます**。
固定値ではないので、他のサービスと衝突しません。同じ認証設定を要求するスイートは
1つのコンテナを共有し、その上で
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
コンテナの再利用で速くなるため）。溜まったコンテナは `rig` コマンド（`rig_cli`）の `prune` で
削除できます。`rig` はこのリポジトリのどのパッケージにも依存として入っていないので、まず
入れる必要があります：

```bash
dart pub global activate rig_cli
```

素の `rig prune` が消すのは、**共有コンテナで作成から 7 日以上経ったもの**と、**専用コンテナで
1 時間以上経ったもの**です。年齢の意味が違うので閾値も違います — 共有コンテナの年齢は
「実行をまたいだ再利用がどれだけ効いているか」ですが、専用コンテナはスイートごとに作られて
終了時に消えるので、その年齢はスイートの実行時間とほぼ等しく、1 時間より古ければ
teardown が走らずに漏れたものと見なせます。ここのテストは共有コンテナを使うので、
テスト直後に叩けば `Nothing to remove.` が返ります：

```bash
rig prune
```

コンテナを種類を問わず全部消したいときは `--all` を付けますが、これは**いま他のセッションが
走らせている統合テストのコンテナも一緒に消します**（専用コンテナも含めて全部消す、という
コマンド自身の警告どおりです）。並行して他のテストが走っていない状態を確認してから使って
ください：

```bash
rig prune --all
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

ユーザーとパスワードはいずれも `test` / `test` です。データベース名は固定の `test_db` では
ありません。上に書いたとおり rig がスイート毎に `test_<パッケージ名>_...` の形で発行するので、
繋ぐときはテストコードと同じく `pg.url`（または `pg.database`）を使ってください。`test_db` は
コンテナの管理用データベースで、テストはここには何も書きません（テーブルは常に 0 個です）。
テスト実行中に実際のデータベース名を覗くには、対象コンテナに対して次を叩きます（テストが
終わると消えるので、実行中だけ有効です）：

```bash
docker exec <コンテナID> psql -U test -d postgres -tAc "select datname from pg_database"
```

ホストポートは rig が**コンテナを作るときに**空いているものを割り当て、そのコンテナを
使い回す間は同じポートを使います(実行ごとに変わるわけではありません)。いずれにせよ
固定値ではないので、手元の別の Postgres と衝突しません。

## CI

**これらの統合テストは CI でも実行されます。** 以前は `docker compose up` を先に叩く必要が
あったので CI では回せませんでしたが、各スイートが自分で必要なコンテナを起動するように
なったので、`ubuntu-latest` の Docker でそのまま動きます（`.github/workflows/test.yml` の
`Test aim_postgres integration` 以降）。

CI のランナーは毎回新品なので、**イメージの pull と initdb を含む初回の経路を通るのは CI だけ**
です。手元では前回のコンテナを再利用するので、そこは飛ばされます。

## トラブルシューティング

### PostgreSQLコンテナが起動しない

`docker ps -a` でコンテナ名を確認し（rig が付けるランダムな名前です）、`docker logs <name>`
でログを確認してください。それでも解決しない場合、壊れているコンテナを消して次回の
`usePostgres()` に作り直させる方法は 2 つあります。

- 対象のコンテナだけ消す: `docker rm -f <name>`
- rig が持っているコンテナを一旦全部消す: `rig prune --all`（**他のセッションが今動かしている
  統合テストのコンテナも一緒に消えます**。並行実行が無いことを確認してから使ってください。
  素の `rig prune`（`--all` 無し）は作成から 7 日以内の共有コンテナを対象にしないので、
  作ったばかりの壊れたコンテナには効きません）

```bash
rig prune --all
dart test -t integration --run-skipped
```

### サーバー側のログを見たい

認証方式の切り分けなど、サーバー側で何が起きているか見たいときは
`usePostgres(auth: ..., verboseLogs: true)` を使います。`log_statement=all` /
`log_connections=on` / `log_disconnections=on` / `log_duration=on` /
`log_line_prefix=...` の5つが付き、`docker logs <name>` で見えるようになります
（既定は `false` で、全スイートのログが膨らむのを避けています）。

## テスト戦略の参考

このテスト戦略は、Dart `postgres`パッケージの実装を参考にしています：

- [isoos/postgresql-dart](https://github.com/isoos/postgresql-dart)
