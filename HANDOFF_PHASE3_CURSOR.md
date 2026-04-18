# Phase 3 — cursor 担当: MCP write ツール + batch_get + readonly モード

## 前提

Phase 1–2 で CLI / MCP / firestore client の最小セットが完成済み。Phase 3 は MCP 側に write ツール 2 種 (`firestore_create_document`, `firestore_delete_document`) と `firestore_batch_get` を追加し、`--readonly` モードで write ツールを無効化する。**あなたの担当は mcp/ と cmd/mcp/ のみ**。firestore/ と cmd/cli/ は copilot が並列で進める。

編集して良いディレクトリ:
- `mcp/`
- `cmd/mcp/`

**編集してはいけない** ディレクトリ:
- `firestore/`, `cmd/cli/`, `test/integration/`, root の `moon.mod.json`

## 契約（凍結）

copilot が並列で追加する firestore client は以下を提供する。**あなたは直接この型を使わず、以下に定義する `FirestoreReader` / `FirestoreWriter` trait を介して呼び出す**（cmd/mcp/main.mbt で trait を impl する）。

copilot が実装する client API（参考、cmd/mcp/main.mbt のみで使用）:
```moonbit
pub enum BatchGetResult {
  Found(@gfs.Document)
  Missing(String)
}
pub async fn FirestoreClient::batch_get_documents(
  self, doc_paths : Array[String]
) -> Array[BatchGetResult] raise @ghttp.HttpError
```

## mcp/server.mbt 変更

### `FirestoreReader` trait 拡張

既存の `get_document` / `list_documents` / `query_collection` に加えて `batch_get` を追加:

```moonbit
pub(open) trait FirestoreReader {
  async get_document(Self, collection_path : String, doc_id : String) -> Json
  async list_documents(
    Self, collection_path : String, page_size : Int?, page_token : String?
  ) -> Json
  async query_collection(
    Self, collection_path : String, field : String, op : String,
    value : Json, limit : Int?
  ) -> Json
  async batch_get(Self, doc_paths : Array[String]) -> Json
}
```

`batch_get` の返り値 Json 形状:
```json
[
  {"found": {<document json>}},
  {"missing": "projects/.../documents/notes/not-here"}
]
```
→ cmd/mcp/main.mbt の impl 側でこの形に整形する責務。server.mbt は pass-through。

### 新 `FirestoreWriter` trait

```moonbit
pub(open) trait FirestoreWriter {
  async create_document(
    Self,
    collection_path : String,
    doc_id : String?,
    fields : Map[String, Json],
  ) -> Json
  async delete_document(
    Self,
    collection_path : String,
    doc_id : String,
  ) -> Unit
}
```

### tool schemas 追加

`tool_schemas()` に以下 3 種を追加:

1. `firestore_batch_get`: params = `{doc_paths: string[]}`（必須）
2. `firestore_create_document`: params = `{collection_path: string, doc_id?: string, fields: object}`（`collection_path` と `fields` 必須）
3. `firestore_delete_document`: params = `{collection_path: string, doc_id: string}`（両方必須）

`tool_schemas()` は **readonly フラグで分岐** する。read-only なら write ツール 2 種を除外。

```moonbit
fn tool_schemas(readonly : Bool) -> Array[Tool] {
  let read = [...]  // 既存 3 + batch_get
  if readonly { return read }
  read + [create_schema, delete_schema]
}
```

### `run_server` シグネチャ変更

```moonbit
pub async fn[R : FirestoreReader, W : FirestoreWriter] run_server(
  reader : R,
  writer : W,
  readonly~ : Bool = false,
) -> Unit
```

`readonly = true` の場合は `writer` の呼び出し箇所に到達しない（tools/list から弾かれ tools/call で弾かれる）。それでも型レベルでは writer を要求する（dummy impl を渡す設計は呼び出し側の自由）。

### tools/list / tools/call の readonly 分岐

- `tools/list` → `tool_schemas(readonly)` を返す
- `tools/call` で write ツール（`firestore_create_document` / `firestore_delete_document`）が呼ばれたとき、`readonly = true` なら `rpc_error(rid, -32600, "Invalid Request: write operations are disabled in readonly mode")` を返す（= ToolResultContent ではなく JSON-RPC エラー。HANDOFF.md 旧版の方針踏襲）
- `readonly = false` なら writer を使って dispatch

### dispatch 追加

既存の `dispatch_tools_call` を拡張:
- `firestore_batch_get`: `doc_paths : Array[String]` を arg_map から取得（型チェック含む）、`reader.batch_get(doc_paths)` 呼び出し、結果を `wrap_tool_result(Text(...))`
- `firestore_create_document`: `collection_path`, `doc_id?`, `fields : Map[String, Json]` を取得、`writer.create_document(...)` 呼び出し
- `firestore_delete_document`: `collection_path`, `doc_id` を取得、`writer.delete_document(...)` → 成功時は `Text("{\"deleted\": \"<cp>/<id>\"}")` で返す

## cmd/mcp/main.mbt 変更

### `Reader` → 名称維持だが両 trait を impl

既存の `Reader` struct に `FirestoreReader` に加えて `FirestoreWriter` を impl:

```moonbit
pub impl @mcp_lib.FirestoreReader for Reader with batch_get(self, doc_paths) {
  let results = self.client.batch_get_documents(doc_paths)
  // results を Json 配列に変換
  let arr : Array[Json] = []
  for r in results {
    match r {
      @firestore.BatchGetResult::Found(doc) =>
        arr.push(Json::object({ "found": @firestore.document_to_json(doc) }))
      @firestore.BatchGetResult::Missing(name) =>
        arr.push(Json::object({ "missing": Json::string(name) }))
    }
  }
  Json::array(arr)
}

pub impl @mcp_lib.FirestoreWriter for Reader with create_document(
  self, collection_path, doc_id, fields
) {
  // fields : Map[String, Json] を Map[String, @gfs.Value] に変換
  let converted : Map[String, @gfs.Value] = {}
  for k, v in fields {
    converted[k] = json_to_value(v)  // 既存ヘルパを再利用
  }
  let doc = self.client.create_document(collection_path, doc_id?, converted)
  @firestore.document_to_json(doc)
}

pub impl @mcp_lib.FirestoreWriter for Reader with delete_document(
  self, collection_path, doc_id
) {
  self.client.delete_document(collection_path, doc_id)
}
```

注意: `json_to_value` が `Json::Object` や `Json::Array` を受け取ったとき現状は `raise @ghttp.HttpError::network_message(...)` している。create 用途では nested object も許容したいかもしれないが、**v1 スコープでは primitive のみで OK**（array/object が来たら既存のエラーを raise）。

### `--readonly` フラグ parse

`main` 関数の冒頭で `@sys.get_cli_args()` を取って `args.iter().any(fn(a) { a == "--readonly" })` を判定:

```moonbit
async fn main {
  let args = @sys.get_cli_args()
  let readonly = args.iter().any(fn(a) { a == "--readonly" })
  match @firestore.Config::from_env() {
    // 既存と同じ分岐を維持
    Ok(cfg) => /* ... */ run_with_client(fc, readonly)
  }
}

async fn run_with_client(client : @firestore.FirestoreClient, readonly : Bool) {
  let reader = Reader::{ client, }
  @mcp_lib.run_server(reader, reader, readonly~)
}
```

同じ `Reader` インスタンスを reader と writer の両方に渡す（型推論で 2 つの trait impl が選ばれる）。

## wbtest

`mcp/server_wbtest.mbt` に以下を追加:

1. **readonly モードで tools/list を叩くと write ツールが返らない**
   - mock Reader + mock Writer（Writer impl は全部 abort しておけば、readonly = true なら到達しないことも兼ねて検証できる）
   - tools/list のレスポンス JSON を parse して tool name 配列を取り出し、`firestore_create_document` / `firestore_delete_document` が **含まれない** ことを assert

2. **readonly = true で write ツールを呼ぶと JSON-RPC error**
   - `tools/call` に `firestore_create_document` を投げ、response の `error.code == -32600` を assert
   - writer は呼ばれないはずなので abort で実装しておけばテストはそれも検証

3. **readonly = false で batch_get が動く**
   - mock Reader::batch_get が既知の Json を返す → tools/call の result の `content[0].text` を parse して一致確認

4. **readonly = false で create / delete がそれぞれ dispatch される**
   - mock Writer::create_document / delete_document を記録して呼ばれたか assert

既存の whitebox テストは全て維持（壊さない）。

## 完了条件

1. `moon check -p ryota0624/firestire_cli/mcp` 通過
2. `moon build --target native cmd/mcp` 通過
3. `moon test -p ryota0624/firestire_cli/mcp` 通過（既存 8/8 + 追加分）
4. 手動確認:
   ```bash
   # readonly モード
   echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | \
     GCP_PROJECT=test-project FIRESTORE_EMULATOR_HOST=http://127.0.0.1:8081 \
     ./mcp.exe --readonly
   # → tools 配列に firestore_create_document / _delete_document が含まれない
   ```

## 参考ファイル

- 既存の `mcp/server.mbt`: `/Users/ryota.suzuki/git/firestire_cli/mcp/server.mbt`
- 既存の `cmd/mcp/main.mbt`: `/Users/ryota.suzuki/git/firestire_cli/cmd/mcp/main.mbt`
- 既存の `mcp/server_wbtest.mbt`（モック Reader のパターン参照）
- MCP 仕様: https://spec.modelcontextprotocol.io/ の `2025-06-18` 版
- MoonBit 構文注意点: `/Users/ryota.suzuki/.claude/CLAUDE.md` の「MoonBit 注意点」節
