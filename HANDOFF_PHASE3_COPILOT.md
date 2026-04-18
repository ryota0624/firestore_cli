# Phase 3 — copilot 担当: firestore lib 拡張 + CLI 機能追加

## 前提

Phase 1–2 で CLI / MCP / firestore client の最小セットが完成済み。Phase 3 は MCP の write ツール・batch_get・readonly モード、CLI の write サブコマンド・認証フラグ追加。**あなたの担当は firestore lib と cmd/cli のみ**。mcp/ と cmd/mcp/ は cursor が並列で進める。

編集して良いディレクトリ:
- `firestore/`
- `cmd/cli/`

**編集してはいけない** ディレクトリ:
- `mcp/`, `cmd/mcp/`, `test/integration/`, root の `moon.mod.json`（これらは自分または cursor が触る）

## 契約（凍結）

cursor が並列で実装する MCP 側はこの契約を前提に書かれる。**シグネチャは変えない**。

### `firestore/client.mbt` 追加

```moonbit
pub enum BatchGetResult {
  Found(@gfs.Document)
  Missing(String)  // 存在しなかったドキュメントの full resource name
}

pub async fn FirestoreClient::batch_get_documents(
  self : FirestoreClient,
  doc_paths : Array[String],  // 各要素は "collection_path/doc_id" 形式（例: "notes/doc-a"）
) -> Array[BatchGetResult] raise @ghttp.HttpError
```

実装方針:
- 各 `doc_path` を `split_doc_path` 相当で `(collection_path, doc_id)` に分割し、`build_document_name` で full resource name に変換
- `@gfs.BatchGetDocumentsRequest::{ documents: Some([name1, name2, ...]), ... }` を組み立てる
- `database` は `"projects/\{self.project}/databases/\{self.database}"`
- `self.service.batch_get_documents(database, request)` 呼び出し
- 戻り値の `Array[BatchGetDocumentsResponse]` を走査し、`found: Some(doc)` → `Found(doc)`、`missing: Some(name)` → `Missing(name)`、両方 None（transaction-only メタデータ）は skip

注意: `cmd/cli/main.mbt` の `split_doc_path` はこのパッケージ外に居るので、`firestore/path.mbt` へ pub 関数として移す（または client.mbt 内に同等のプライベート関数を書く）。**path.mbt に `pub fn split_doc_path(path : String) -> Result[(String, String), String]` として移すのが推奨。** その場合 `cmd/cli/main.mbt` 側は `@firestore.split_doc_path` を呼ぶように差し替え。

### `firestore/auth_adc.mbt` 追加

```moonbit
pub async fn build_production_client_from_service_account(
  path : String,
) -> Result[@gcore.GoogleClient, String]
```

実装方針:
- `@fs.read_file(path)` でファイル内容を読む（読み込み失敗は `Err("failed to read credentials: \{path}")`）
- `@googleauth.parse_service_account_key(content)` でパース
- `@googleauth.from_service_account_credentials(creds)` で `GoogleClientCredentials` 生成
- そこから `GoogleAuthClient` / `GoogleApiClient` を構築して access token を取得
- `@gcore.GoogleClient::new(fn() { token })` を返す

`googleauth` の API 確認先: `/Users/ryota.suzuki/git/moonbit_googleauth/lib/pkg.generated.mbti`

もし `parse_service_account_key` + `from_service_account_credentials` から `GoogleAuthClient` への経路が既存の `auto_detect_and_authenticate` ベースで書けない場合、**簡易代替案** として `GOOGLE_APPLICATION_CREDENTIALS` 環境変数を設定してから `auto_detect_and_authenticate()` を呼ぶ実装でも可（その場合は関数内で `@sys.set_env_var` 相当を使う。`mizchi/x/sys` にあるか確認すること）。

### `firestore/moon.pkg`

`@fs` を使う場合は import に `"moonbitlang/core/fs" @fs` を追加。ただし現状 native のみ対応でよい。

## CLI 機能追加

### `cmd/cli/main.mbt` USAGE 更新

```
firestire <subcommand> [options]
  get <collection_path>/<doc_id>
  list <collection_path> [--page-size N] [--page-token TOKEN]
  query <collection_path> --where FIELD=VALUE [--op OP] [--limit N]
  create <collection_path> [--doc-id ID] --fields JSON
  delete <collection_path>/<doc_id>

Global options:
  --project ID             override GCP_PROJECT
  --database ID            override FIRESTORE_DATABASE (default: "(default)")
  --credentials PATH       use service account JSON at PATH (overrides ADC)

Environment:
  GCP_PROJECT (or GOOGLE_CLOUD_PROJECT)   required (or --project)
  FIRESTORE_DATABASE                       default: (default)
  FIRESTORE_EMULATOR_HOST                  emulator mode when set
```

### 新サブコマンド `create`

```
firestire create notes --doc-id doc-a --fields '{"title":"alpha","count":1}'
```

実装:
- `--fields JSON` は必須。`@json.parse(str)` で Json に変換
- Json は必ず `Json::Object(map)` 前提で、各値を `@gfs.Value` に変換（cmd/mcp/main.mbt の `json_to_value` と同じ方針。**`firestore/value.mbt` に `pub fn json_to_value(Json) -> Result[@gfs.Value, String]` として移すのが推奨** — mcp 側からも使えるようにする）
- `--doc-id` は optional（なしなら Firestore が自動採番）
- 成功時は作成された Document を JSON で stdout 出力

### 新サブコマンド `delete`

```
firestire delete notes/doc-a
```

実装:
- 引数 1 個（`collection_path/doc_id`）を `split_doc_path` で分解
- `fc.delete_document(cp, doc_id)` 呼び出し
- 成功時は `{"deleted": "collection_path/doc_id"}` を stdout 出力

### グローバルフラグ

`--project` / `--database` は `Config::from_env()` 後に上書き。`--credentials` は emulator モード **でない** 場合のみ有効 (`emulator_host` が Some なら無視 or 警告を stderr)。

実装順序の参考:
1. `get_flag` はすでにあるのでそれで引数を拾う
2. `args` 解析を拡張して、サブコマンド解析前に global flag をチェック & 除去
3. `build_production_client` の代わりに `--credentials` 指定時は `build_production_client_from_service_account(path)` を呼ぶ

## テスト

### wbtest で追加

`firestore/path_wbtest.mbt` に `split_doc_path` のケース（移動する場合）:
- `"notes/doc-a"` → `Ok(("notes", "doc-a"))`
- `"users/alice/posts/1"` → `Ok(("users/alice/posts", "1"))`
- `"notes"` → `Err(_)` (single segment)
- `"a/b/c"` → `Err(_)` (even collection path count)

`firestore/value_wbtest.mbt` に `json_to_value` のケース（移動する場合）:
- `Json::string("x")` → string value
- `Json::number(1.0)` → integer value (whole number)
- `Json::number(1.5)` → double value
- `Json::boolean(true)` → boolean value
- `Json::null()` → null value
- `Json::array([...])` → Err（サポート外）
- `Json::object(...)` → Err

## 完了条件

1. `moon check -p ryota0624/firestire_cli/firestore` 通過
2. `moon build --target native cmd/cli` 通過
3. `moon test -p ryota0624/firestire_cli/firestore` 通過（既存 8/8 + 追加分）
4. CLI 動作確認（docker で emulator 起動後）:
   ```bash
   ./cli.exe create notes --doc-id smoke --fields '{"title":"x","count":1}'
   ./cli.exe get notes/smoke
   ./cli.exe delete notes/smoke
   ```

## 参考ファイル

- googleapis Firestore API: `/Users/ryota.suzuki/git/moonbit_googleapis/generated/firestore/pkg.generated.mbti`
- googleauth API: `/Users/ryota.suzuki/git/moonbit_googleauth/lib/pkg.generated.mbti`
- 既存の CLI 実装: `/Users/ryota.suzuki/git/firestire_cli/cmd/cli/main.mbt`
- 既存の client 実装: `/Users/ryota.suzuki/git/firestire_cli/firestore/client.mbt`
- MoonBit 構文注意点: `/Users/ryota.suzuki/.claude/CLAUDE.md` の「MoonBit 注意点」節
