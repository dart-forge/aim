# 統合テストの rig 移行とマージの前提

`aim_postgres` と `aim_orm_codegen` の統合テストは、Docker Compose を使わず `rig`
(`package:rig`, `package:rig_postgres`) の上で動くようになった。この変更は**このブランチのままではマージできない**。理由と、マージできる状態にするために必要なことをここに書き残す。

## なぜマージできないか

統合テストは `rig` と `rig_postgres` に依存している。この2つはまだ pub.dev に公開されておらず、
ルートの `pubspec.yaml` は次のように `dependency_overrides` で**隣のディレクトリにある rig の
チェックアウト**を指すことでしか解決できない。

```yaml
dependency_overrides:
  rig:
    path: ../rig/packages/rig
  rig_postgres:
    path: ../rig/packages/rig_postgres
```

このため、このブランチを取り込むと以下の両方が失敗する：

- **aim だけを clone した人**の `dart pub get`(`../rig` が存在しないので path 依存が解決できない)
- **CI** の `dart pub get`(CI のチェックアウトは aim 単体で、どこにも `rig` が無い)

aim 単体では `rig` の実体を用意する手段がまだ無い、というのがマージできない理由そのものである。

## マージの前提

次のどちらかが成立するまで、このブランチはマージできない。

- (a) `rig` / `rig_postgres` が pub.dev に公開され、`dependency_overrides` を外して
  通常の hosted 依存(`pubspec.yaml` の `dependencies` に `rig: ^x.y.z` のように書くだけ)に
  置き換えられること。
- (b) それまでの間、CI が aim をチェックアウトするのに合わせて `rig` も並びの位置に
  チェックアウトする手順を持つこと(`dart pub get` が通る配置を CI 側で再現する)。

いずれも整うまでは、このブランチを main に入れても CI が壊れる。

## 手元で統合テストを動かす方法(今のところ)

`aim` と `rig` を同じ親ディレクトリに並べて置く。

```
some-parent-dir/
├── aim/   (このリポジトリ)
└── rig/
```

その状態で、aim のルートで通常どおり依存解決する。

```bash
dart pub get
```

`../rig` が見つかれば `dependency_overrides` が解決し、各パッケージの統合テストが動く。

## テストを書く人にとって何が変わったか

- **Compose ファイルは無い。** 各パッケージの `test/integration/docker-compose.yml` と、
  それを手で起動していた `docker_stack.dart` は削除した。統合テストファイルの先頭で
  `usePostgres()`(`package:rig_postgres`)を呼ぶだけで、rig がコンテナを自分で用意する。
- **固定ポートは無い。** ポートは実行ごとに動的に割り当てられるので、手元で動かしている
  別の Postgres と衝突しない。
- **スイート毎にデータベースが分かれる。** 同じ認証設定を要求するスイートは1つのコンテナを
  共有するが、その上でスイート毎に専用のデータベースが切られるため、並行して走っても
  互いのテーブルを見ない。
- **コンテナはテスト終了後も意図的に残す。** 次回の実行がコンテナの再利用で速くなるため、
  テストが終わってもコンテナは落とさない。溜まったコンテナの掃除は `rig` コマンド
  (`rig_cli`) の `prune` サブコマンドで行うが、`rig` はどのパッケージの依存にも入っていない
  ので、先に `dart pub global activate -s path ../rig/packages/rig_cli` で入れる必要がある。
  素の `rig prune` が消すのは作成から 7 日以上経った共有コンテナだけで、作ったばかりの
  コンテナには効かない。コンテナ全部を種類問わず消すには `rig prune --all` が要るが、これは
  他のセッションが今使っている専用コンテナも一緒に消すので、並行実行中は注意が必要
  （詳細は `packages/aim_postgres/test/README.md` の「コンテナを止める」節）。
