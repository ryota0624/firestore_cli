# Copilot 委譲: firestore/ パッケージ実装

## ゴール

`/Users/ryota.suzuki/git/firestire_cli/firestore/` パッケージを完成させる。CLI と MCP server 両方から使う Firestore ラッパー層。完了条件は `moon check -p ryota0624/firestire_cli/firestore` と `moon test -p ryota0624/firestire_cli/firestore` が通ること。

## 全体プラン

プラン全体は `/Users/ryota.suzuki/.claude/plans/hands-off-ryota0624-googleapis-0-4-0-goofy-eich.md` 参照。

## パッケージ構造と作成ファイル

```
firestore/
├── moon.pkg                # import を自分で追記
├── path.mbt                # pure: collection path 分解
├── value.mbt               # pure: Value<->Json 変換ヘルパ
├── config.mbt              # pure: Config::from_env
├── client.mbt              # FirestoreClient: wrap @gfs.FirestoreService
├── auth_emulator.mbt       # NoAuthHttpClient + dummy token
├── auth_adc.mbt            # googleauth 結線
├── path_wbtest.mbt         # split_collection_path のテスト
└── value_wbtest.mbt        # value_to_json のテスト
```

既存の `placeholder.mbt` は **削除** してよい（自分で作った placeholder）。

## moon.pkg に書くべき import

```
import {
  "ryota0624/googleapis/core" @gcore,
  "ryota0624/googleapis/http" @ghttp,
  "ryota0624/googleapis/generated/firestore" @gfs,
  "ryota0624/googleauth/lib" @googleauth,
  "mizchi/x/sys" @sys,
  "moonbitlang/core/json",
}
```

## API 契約（公開シグネチャ）

### `firestore/path.mbt`

```moonbit
///| 奇数セグメントの collection path を (parent_suffix, collection_id) に分解する。
/// 例: "notes" → Ok(("", "notes"))、"users/alice/posts" → Ok(("users/alice", "posts"))
/// 偶数セグメントや空文字セグメントを含む場合は Err を返す。
pub fn split_collection_path(path : String) -> Result[(String, String), String]

///| "projects/{project}/databases/{database}/documents" に parent_suffix があれば "/" でつなぐ。
pub fn build_parent(project : String, database : String, parent_suffix : String) -> String

///| get_document / delete_document 用の完全修飾名を組み立てる。
pub fn build_document_name(project : String, database : String, collection_path : String, doc_id : String) -> String
```

### `firestore/value.mbt`

```moonbit
pub fn sv(value : String) -> @gfs.Value        // string_value
pub fn iv(value : Int64) -> @gfs.Value         // integer_value (Value の integer_value は String 型)
pub fn bv(value : Bool) -> @gfs.Value          // boolean_value
pub fn dv(value : Double) -> @gfs.Value        // double_value
pub fn nullv() -> @gfs.Value                   // null_value
///| Value を CLI / MCP 出力用の平坦な Json に変換する。
/// 例: Value{string_value: Some("hello")} → String("hello")
///     Value{integer_value: Some("42")} → Number(42.0) もしくは String ("42" のまま) — 方針統一可
pub fn value_to_json(v : @gfs.Value) -> Json

///| Document を {name, fields, create_time, update_time} を持つ Json Object に変換する。
/// fields は Map[String, Json] として各 Value を value_to_json で変換する。
pub fn document_to_json(doc : @gfs.Document) -> Json
```

### `firestore/config.mbt`

```moonbit
pub struct Config {
  project : String
  database : String         // default: "(default)"
  emulator_host : String?   // Some(host) なら emulator モード、None なら本番 ADC
}

///| 環境変数から読み出す:
/// - GCP_PROJECT or GOOGLE_CLOUD_PROJECT (必須)
/// - FIRESTORE_DATABASE (default: "(default)")
/// - FIRESTORE_EMULATOR_HOST (optional: set なら emulator モード)
/// 必須項目が無ければ Err("missing GCP_PROJECT") など。
pub fn Config::from_env() -> Result[Config, String]
```

### `firestore/client.mbt`

```moonbit
pub struct FirestoreClient {
  service : @gfs.FirestoreService
  project : String
  database : String
}

pub fn FirestoreClient::new(
  client : @gcore.GoogleClient,
  project : String,
  database~ : String = "(default)",
  base_url? : String,
) -> FirestoreClient

pub async fn FirestoreClient::get_document(
  self : FirestoreClient,
  collection_path : String,
  doc_id : String,
) -> @gfs.Document raise @ghttp.HttpError

pub async fn FirestoreClient::list_documents(
  self : FirestoreClient,
  collection_path : String,
  page_size? : Int,
  page_token? : String,
) -> @gfs.ListDocumentsResponse raise @ghttp.HttpError

pub async fn FirestoreClient::query_collection(
  self : FirestoreClient,
  collection_path : String,
  field : String,
  op : String,                 // "EQUAL" | "LESS_THAN" | "GREATER_THAN" など Firestore REST の演算子文字列
  value : @gfs.Value,
  limit? : Int,
) -> Array[@gfs.Document] raise @ghttp.HttpError

// 統合テスト fixture 経路。MCP public には出さない。
pub async fn FirestoreClient::create_document(
  self : FirestoreClient,
  collection_path : String,
  doc_id? : String,
  fields : Map[String, @gfs.Value],
) -> @gfs.Document raise @ghttp.HttpError

pub async fn FirestoreClient::delete_document(
  self : FirestoreClient,
  collection_path : String,
  doc_id : String,
) -> Unit raise @ghttp.HttpError
```

### `firestore/auth_emulator.mbt`

```moonbit
// NoAuthHttpClient: Authorization ヘッダを剥がして delegate する HttpClient 実装
struct NoAuthHttpClient {
  inner : @ghttp.DefaultHttpClient
}
pub impl @ghttp.HttpClient for NoAuthHttpClient with request(self, req) { ... }

///| emulator_host は "http://127.0.0.1:8081" のような URL。get_token は常に "dummy" を返す。
pub async fn build_emulator_client() -> @gcore.GoogleClient
```

### `firestore/auth_adc.mbt`

```moonbit
///| googleauth の auto_detect_and_authenticate → get_access_token で得たトークンを
/// @gcore.GoogleClient::new(fn() { token }) に渡す。失敗時は Err。
pub async fn build_production_client() -> Result[@gcore.GoogleClient, String]
```

## 参照実装（写経元）

**必ず開いて形を真似ること**：

1. `/Users/ryota.suzuki/git/app_skalton/e2e/helpers.mbt`
   - `start_firestore_emulator`, `NoAuthHttpClient` impl, `build_emulator_app_context`
2. `/Users/ryota.suzuki/git/moonbit_googleapis/e2e/firestore/e2e_test.mbt`
   - `sv` / `iv` Value ヘルパ、create/get/delete シナリオ、run_query の組み立て方
3. `/Users/ryota.suzuki/git/moonbit_googleapis/generated/firestore/pkg.generated.mbti`
   - `FirestoreService` の全メソッドシグネチャ、`Document`, `Value`, `RunQueryRequest` 等の struct 定義
4. `/Users/ryota.suzuki/git/moonbit_googleauth/pkg.generated.mbti` と `lib/pkg.generated.mbti`
   - `auto_detect_and_authenticate` / `get_access_token` のシグネチャ

## MoonBit 構文の注意点

`/Users/ryota.suzuki/.claude/CLAUDE.md` の「MoonBit 注意点」節を参照。特に：

- `?` 演算子（Result 早期リターン）は **存在しない**。`match` で明示的にハンドリング
- `not(expr)` は非推奨。`!expr` を使う
- `substring()` は非推奨。`str[:10].to_string()` のようにスライス構文を使う
- 文字列結合 `+` を改行する場合、`+` を **行末** に置く
- `_test.mbt`（blackbox）では他パッケージの struct を直接構築できない。公開コンストラクタが必要
- `async fn main` には `moonbitlang/async` パッケージの import が必要（moon.pkg と moon.mod.json 両方）
- `moon info` はデフォルト wasm-gc。async fn main を含むパッケージがある場合は `-p` でlib のみ指定

## テスト（wbtest, Docker 不要）

### `path_wbtest.mbt`

```moonbit
test "split_collection_path: single segment" {
  assert_eq(split_collection_path("notes"), Ok(("", "notes")))
}
test "split_collection_path: three segments" {
  assert_eq(split_collection_path("users/alice/posts"), Ok(("users/alice", "posts")))
}
test "split_collection_path: even segments rejected" {
  // "users/alice" は document path なので Err
  ...
}
test "split_collection_path: empty segment rejected" {
  ...
}
```

### `value_wbtest.mbt`

`sv("x") |> value_to_json` が `Json::String("x")` を返す等の round-trip。

## 完了条件

```bash
moon check -p ryota0624/firestire_cli/firestore   # no warnings, no errors
moon test -p ryota0624/firestire_cli/firestore    # wbtest all green
moon info -p ryota0624/firestire_cli/firestore    # .mbti regenerated
```

## スコープ外

- `update_document` / `batch_get` / `run_aggregation_query` は実装しない（次フェーズ）
- CLI / MCP のエントリポイントは触らない（cmd/cli, cmd/mcp, mcp/ は別担当）
- `moon.mod.json` は変更しない（依存は確定済み）
