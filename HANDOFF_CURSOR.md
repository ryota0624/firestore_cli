# Cursor 委譲: mcp/ パッケージ + cmd/mcp/ エントリ実装

## ゴール

1. `/Users/ryota.suzuki/git/firestire_cli/mcp/` — MCP (Model Context Protocol) プロトコル層
2. `/Users/ryota.suzuki/git/firestire_cli/cmd/mcp/main.mbt` — stdio JSON-RPC を回すエントリポイント

完了条件：
- `moon check -p ryota0624/firestire_cli/mcp` と `moon check -p ryota0624/firestire_cli/cmd/mcp` が通る
- `moon test -p ryota0624/firestire_cli/mcp` (wbtest) が通る
- `moon build --target native cmd/mcp` が通る

## 全体プラン

プラン全体は `/Users/ryota.suzuki/.claude/plans/hands-off-ryota0624-googleapis-0-4-0-goofy-eich.md` 参照。

## 作成ファイル

```
mcp/
├── moon.pkg
├── types.mbt             # JsonRpcRequest / Response / Error / Tool / ToolResult
├── codec.mbt             # JSON-RPC 2.0 encode/decode
├── transport.mbt         # send_message / recv_message / log
├── server.mbt            # run_server + FirestoreReader trait
├── codec_wbtest.mbt      # round-trip
└── server_wbtest.mbt     # mock Reader で dispatch テスト

cmd/mcp/
├── moon.pkg              # is-main, imports @firestore + @mcp
└── main.mbt              # Config → auth → reader impl → run_server
```

既存の `mcp/placeholder.mbt` と `cmd/mcp/main.mbt` (placeholder) は **上書き** してよい。

## moon.pkg に書くべき import

### `mcp/moon.pkg`

```
import {
  "mizchi/x/stdio" @stdio,
  "moonbitlang/core/json",
  "moonbitlang/async",
}
```

### `cmd/mcp/moon.pkg`

```
import {
  "ryota0624/firestire_cli/firestore" @firestore,
  "ryota0624/firestire_cli/mcp" @mcp,
  "ryota0624/googleapis/generated/firestore" @gfs,
  "moonbitlang/core/json",
}

options(
  "is-main": true,
)
```

## API 契約

### `mcp/types.mbt`

```moonbit
pub struct JsonRpcRequest {
  jsonrpc : String
  id : Json?           // None = notification
  method_ : String
  params : Json?
}

pub struct JsonRpcResponse {
  jsonrpc : String
  id : Json?
  result : Json?
  error : JsonRpcError?
}

pub struct JsonRpcError {
  code : Int
  message_ : String
  data : Json?
}

pub struct Tool {
  name : String
  description : String
  input_schema : Json    // JSON Schema 形式。出力時は "inputSchema" キー
}

pub enum ToolResultContent {
  Text(String)
  Error(String)
}
```

### `mcp/codec.mbt`

```moonbit
pub fn JsonRpcRequest::from_json(j : Json) -> Result[JsonRpcRequest, String]
pub fn JsonRpcResponse::to_json(self : JsonRpcResponse) -> Json
pub fn Tool::to_json(self : Tool) -> Json   // "inputSchema" (camelCase) で出力
pub fn ToolResultContent::to_json(self : ToolResultContent) -> Json
// Text → {type: "text", text: s}
// Error → {type: "text", text: msg, isError: true}  は呼び出し側で isError フラグを別に付ける
```

### `mcp/transport.mbt`

`mizchi/x/stdio` を使う。

```moonbit
///| stdout へ JSON を改行区切りで送信
pub async fn send_message(payload : Json) -> Unit raise

///| stdin から 1 行読んで JSON にパース
pub async fn recv_message() -> Json raise

///| stderr に診断ログを書く（改行付き）
pub fn log(msg : String) -> Unit
```

### `mcp/server.mbt`

firestore パッケージへ直接依存せず、呼び出し側が trait を impl する：

```moonbit
pub trait FirestoreReader {
  get_document(Self, collection_path : String, doc_id : String) -> Json raise
  list_documents(Self, collection_path : String, page_size : Int?, page_token : String?) -> Json raise
  query_collection(
    Self,
    collection_path : String,
    field : String,
    op : String,
    value : Json,        // CLI/MCP で素の JSON 値を受け取り、reader 側で @gfs.Value に組み立てる
    limit : Int?,
  ) -> Json raise
}

pub const PROTOCOL_VERSION : String = "2025-06-18"

pub async fn run_server[R : FirestoreReader](reader : R) -> Unit
```

`run_server` は stdin/stdout ループで以下を処理する：

- `initialize` → `{protocolVersion, capabilities: {tools: {}}, serverInfo: {name: "firestire-mcp", version: "0.1.0"}}`
- `tools/list` → 3 ツール配列
- `tools/call` → name で dispatch → `ToolResultContent` を `{content: [...], isError: bool}` で返す
- `notifications/*` (特に `notifications/initialized`) → response を返さない
- 未知 method → `{error: {code: -32601, message: "Method not found"}}`
- JSON parse 失敗 → `{error: {code: -32700, message: "Parse error"}}`

登録する 3 ツール（inputSchema は JSON Schema）：

1. `firestore_get_document` — `{collection_path, doc_id}`
2. `firestore_list_documents` — `{collection_path, page_size?, page_token?}`
3. `firestore_query_collection` — `{collection_path, field, op, value, limit?}`

### `cmd/mcp/main.mbt`

```moonbit
struct Reader {
  client : @firestore.FirestoreClient
}

pub impl @mcp.FirestoreReader for Reader with get_document(self, collection_path, doc_id) {
  let doc = self.client.get_document(collection_path, doc_id)  // await & catch
  @firestore.document_to_json(doc)
}
// list_documents, query_collection も同様

async fn main {
  let cfg = match @firestore.Config::from_env() {
    Ok(c) => c
    Err(e) => {
      @mcp.log("config error: \{e}")
      ... exit non-zero
    }
  }
  let client = match cfg.emulator_host {
    Some(host) => @firestore.build_emulator_client()  // 注: emulator_host を渡す API にする
      |> ...
    None => @firestore.build_production_client() |> ...
  }
  let fc = @firestore.FirestoreClient::new(client, cfg.project, database=cfg.database, base_url=?)
  let reader = Reader::{ client: fc }
  @mcp.run_server(reader)
}
```

※ firestore の API の詳細はコンパイル時に copilot が固めている HANDOFF_COPILOT.md の契約を参照。

## 参照実装（必読）

- MCP spec: `https://spec.modelcontextprotocol.io/` の `2025-06-18` 版
- `ryota0624/moonbit_googleauth/cmd/main/main.mbt` — `async fn main` + `mizchi/x/stdio` の使い方
- `mizchi/x/stdio` の moon.pkg: `~/.moon/registry/cache/mizchi/x/0.1.3/...` または `app_skalton/.mooncakes/mizchi/x/src/stdio/`

## MoonBit 構文の注意点

`/Users/ryota.suzuki/.claude/CLAUDE.md` の「MoonBit 注意点」節：

- `async fn main` には `moonbitlang/async` の import が必要（moon.pkg と moon.mod.json 両方。0.16.6 は moon.mod.json に既に入っている）
- `?` 演算子（Result 早期リターン）は存在しない。`match` で明示ハンドル
- `not(x)` → `!x`、`substring()` → `str[:n].to_string()`
- `println` は cmd/cli 側のみ。MCP ループ中は絶対 stdout に書かない (JSON-RPC 以外)。診断は `@mcp.log` 経由で stderr へ

## テスト（wbtest, Docker 不要）

### `codec_wbtest.mbt`

```moonbit
test "JsonRpcRequest round-trip" {
  let raw : Json = Json::from_string(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}",
  ).unwrap()
  let req = JsonRpcRequest::from_json(raw).unwrap()
  assert_eq(req.method_, "tools/list")
  ...
}
```

### `server_wbtest.mbt`

mock の FirestoreReader を定義して dispatch を検証：

```moonbit
struct MockReader {
  ...
}
impl FirestoreReader for MockReader with get_document(self, collection_path, doc_id) {
  Json::Object({"name": Json::String("projects/.../documents/\{collection_path}/\{doc_id}")})
}
// list_documents / query_collection も同様

test "initialize returns protocolVersion" { ... }
test "tools/list returns 3 tools" { ... }
test "tools/call firestore_get_document dispatches" { ... }
test "notifications/initialized returns no response" { ... }
test "unknown method returns -32601" { ... }
```

`run_server` 自体は stdin/stdout ループなのでテストしづらい。dispatch ロジックを内部関数に切り出して（例: `handle_request(req : JsonRpcRequest, reader : R) -> JsonRpcResponse?`）、その単体を wbtest する。

## 完了条件

```bash
moon check -p ryota0624/firestire_cli/mcp          # no warnings, no errors
moon check -p ryota0624/firestire_cli/cmd/mcp
moon test -p ryota0624/firestire_cli/mcp           # wbtest all green
moon build --target native cmd/mcp                 # binary builds
moon info -p ryota0624/firestire_cli/mcp           # .mbti regenerated
```

## スコープ外

- `--readonly` モード
- `firestore_create_document` / `firestore_delete_document` の MCP 公開（読み取り系 3 つのみ）
- `update_document` / `batch_get` 等
- `moon.mod.json` は変更しない
