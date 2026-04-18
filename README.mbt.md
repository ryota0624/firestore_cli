# firestire_cli

MoonBit 製の Firestore 操作ツール。CLI と MCP サーバーの 2 バイナリを提供する。

## 構成

- `cmd/cli` — `get` / `list` / `query` サブコマンドを持つ Firestore CLI
- `cmd/mcp` — stdio JSON-RPC で動く Model Context Protocol サーバー
- `firestore` — `ryota0624/googleapis@0.4.0` をラップした共通クライアント層
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

# コレクション一覧 (ページング対応)
./cli.exe list notes --page-size 10

# フィルタクエリ
./cli.exe query notes --where title=alpha --op EQUAL --limit 5
```

本番接続には `ryota0624/googleauth` の Application Default Credentials (ADC) を使う。`gcloud auth application-default login` 等で認証済みであれば追加設定不要。

## MCP サーバー使用例

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | \
  GCP_PROJECT=test-project FIRESTORE_EMULATOR_HOST=http://127.0.0.1:8081 \
  ./mcp.exe
```

公開する tool は `firestore_get_document` / `firestore_list_documents` / `firestore_query_collection` の 3 種。

## テスト

```bash
# 軽量テスト（Docker 不要）
moon test -p ryota0624/firestire_cli/firestore
moon test -p ryota0624/firestire_cli/mcp

# 統合テスト（Docker 必須）
moon test -p ryota0624/firestire_cli/test/integration --target native
```

## 依存

- `ryota0624/googleapis` 0.4.0
- `ryota0624/googleauth` 0.1.0
- `ryota0624/moonbit_test_containers` 0.0.5
- `moonbitlang/async` 0.16.6
- `mizchi/x` 0.1.3
