# firestore_cli

MoonBit 製の Firestore 操作ツール。CLI と MCP サーバーの 2 バイナリを提供する。

## 構成

- `cmd/cli` — Firestore CLI。`get` / `list` / `list-collections` / `query` / `aggregate` / `create` / `delete`
- `cmd/mcp` — stdio JSON-RPC で動く Model Context Protocol サーバー
- `firestore` — `ryota0624/googleapis` をラップした共通クライアント層
- `mcp` — JSON-RPC 2.0 と tool dispatch を実装した MCP ライブラリ層
- `test/integration` — `google/cloud-sdk:emulators` を `moonbit_test_containers` で起動する統合テスト

## ビルド

```bash
moon build --target native cmd/cli   # → _build/native/release/build/cmd/cli/cli.exe
moon build --target native cmd/mcp   # → _build/native/release/build/cmd/mcp/mcp.exe
```

## 環境変数

| 変数 | 既定値 | 用途 |
| ---- | ------ | ---- |
| `GCP_PROJECT`（または `GOOGLE_CLOUD_PROJECT`） | 必須 | プロジェクト ID |
| `FIRESTORE_DATABASE` | `(default)` | データベース ID |
| `FIRESTORE_EMULATOR_HOST` | 未設定 | 設定時はエミュレータ向け (`http://127.0.0.1:8081` 等)。未設定なら ADC 認証で本番接続 |

## CLI 使用例

```bash
# エミュレータ起動
docker run -d -p 8081:8081 google/cloud-sdk:emulators \
  gcloud beta emulators firestore start --host-port=0.0.0.0:8081 --project=test-project

export GCP_PROJECT=test-project
export FIRESTORE_EMULATOR_HOST=http://127.0.0.1:8081

# 単一ドキュメント取得
./cli.exe get users/alice

# コレクション配下のドキュメント一覧
./cli.exe list notes --page-size 10

# コレクション ID 一覧 (ルート)
./cli.exe list-collections

# サブコレクション ID 一覧 (users/alice の配下)
./cli.exe list-collections --parent users/alice

# 単一条件クエリ
./cli.exe query notes --where title=alpha --op EQUAL --limit 5

# AND 複合条件 + ソート + ページング
./cli.exe query notes \
  --and status=published:EQUAL \
  --and count=0:GREATER_THAN \
  --order created_at:desc \
  --limit 20

# クエリ実行プランを取得 (--analyze で実行統計も取得)
./cli.exe query notes --where title=alpha --op EQUAL --explain --analyze

# 集計クエリ (count / sum / avg)
./cli.exe aggregate notes --count total --sum count:sum_count --avg count:avg_count

# where 条件付き集計
./cli.exe aggregate notes --count --where status=published --op EQUAL

# 集計クエリの explain
./cli.exe aggregate notes --count --explain --analyze
```

本番接続には `ryota0624/googleauth` の Application Default Credentials (ADC) を使う。`gcloud auth application-default login` 等で認証済みであれば追加設定不要。`--credentials PATH` でサービスアカウント JSON を直接指定することもできる。

## MCP サーバー使用例

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | \
  GCP_PROJECT=test-project FIRESTORE_EMULATOR_HOST=http://127.0.0.1:8081 \
  ./mcp.exe
```

公開する tool は以下:

- `firestore_get_document` — 単一ドキュメント取得
- `firestore_list_documents` — コレクション配下のドキュメント一覧
- `firestore_list_collection_ids` — ルート/サブコレクションの ID 一覧 (`parent_doc_path` 省略でルート)
- `firestore_query_collection` — 構造化クエリ (単一 `field`/`op`/`value` 互換スキーマと、複合 `filter` / `order_by` / `start_at` / `end_at` / `offset` / `limit` を両方受理)
- `firestore_aggregate` — COUNT / SUM / AVG (`where` 条件併用可)
- `firestore_explain_query` — クエリプラン取得 (`analyze=true` で実行統計も)
- `firestore_explain_aggregate` — 集計クエリのプラン取得
- `firestore_batch_get` — 複数ドキュメントの一括取得
- `firestore_create_document` / `firestore_delete_document` — 書き込み系 (読み取り専用モードでは無効化)

## テスト

```bash
# 軽量テスト（Docker 不要）
moon test -p ryota0624/firestore_cli/firestore
moon test -p ryota0624/firestore_cli/mcp

# 統合テスト（Docker 必須）
moon test -p ryota0624/firestore_cli/test/integration --target native
```

統合テストでは Firestore エミュレータコンテナを起動し、以下をカバー:

- CRUD 一巡 (create / get / list / query / delete)
- `listCollectionIds` (ルート列挙・サブコレクション列挙)
- 集計 (COUNT / SUM / AVG / where 条件)
- 複合クエリ (CompositeFilter AND / order_by / cursor ページング)
- explain (analyze=false/true)

※ エミュレータは `listCollectionIds` / explain を部分的にしかサポートしない場合がある。該当テストはレスポンスエラー時に早期 return してスキップする形になっている。
