# Firestore MCP Server — Implementation Handoff

## Mission

Verify, fix, and complete a MoonBit implementation of an MCP (Model Context Protocol) server that exposes Firestore CRUD operations as tools. The skeleton has been written but **never compiled** — your job is to make `moon build` and `moon test` pass, then fill remaining gaps.

## Project location

`firestore_mcp/` (this directory)

## Tech stack

- **Language**: MoonBit (native target)
- **Dependencies** (declared in `moon.mod.json`):
  - `ryota0624/googleapis` v0.2.2 — Firestore REST client (https://github.com/ryota0624/moonbit_googleapis)
  - `ryota0624/googleauth` v0.1.0 — ADC + service account auth (https://github.com/ryota0624/moonbit_googleauth)
  - `ryota0624/moonbit_test_containers` v0.0.4 — Docker-based integration tests (https://github.com/ryota0624/moonbit_test_containers)
  - `moonbitlang/async` v0.16.6 — async runtime, stdio, io
- **Transport**: stdio (newline-delimited JSON-RPC), no C FFI
- **Auth**: ADC via `auto_detect_and_authenticate()` (production) / dummy token (emulator)

## Architecture

```
firestore_mcp/
├── moon.mod.json
├── mcp/
│   ├── types/      types.mbt + codec.mbt    # JSON-RPC 2.0 types & serialization
│   ├── transport/  transport.mbt            # @stdio.stdin/stdout/stderr
│   └── server/     server.mbt              # Tool registry & dispatch
├── firestore/      client.mbt              # FirestoreClient wrapping @gfs.FirestoreService
├── cmd/main/       main.mbt                # Entry: parse flags → auth → MCP loop
└── test/firestore_integration/
    ├── emulator.mbt                        # Spawns gcloud Firestore emulator
    └── firestore_test.mbt                  # 22 tests (Docker required for ~13 of them)
```

## What's already implemented

### MCP tools exposed (6 total)

| Tool | Read/Write | Notes |
|------|------------|-------|
| `firestore_get_document` | R | by `collection_path` + `doc_id` |
| `firestore_list_documents` | R | with `page_size`, `page_token` |
| `firestore_query_collection` | R | structured query with field filters |
| `firestore_batch_get` | R | true multi-doc (uses `Array[BatchGetDocumentsResponse]`) |
| `firestore_create_document` | W | blocked in `--readonly` mode |
| `firestore_delete_document` | W | blocked in `--readonly` mode |

### Subcollection support

Collection paths use slash-delimited form with **odd** segment count:
- `notes` → root collection
- `users/alice/posts` → subcollection
- `a/1/b/2/c` → deep subcollection
- `users/alice` → invalid (even count = document path)

`split_collection_path()` in `firestore/client.mbt` handles parsing.

### Read-only mode

`firestore-mcp --readonly` filters write tools from `tools/list` and rejects write `tools/call` with `INVALID_REQUEST` (-32600).

### Environment variables

- `GCP_PROJECT` or `GOOGLE_CLOUD_PROJECT` — required
- `FIRESTORE_DATABASE` — defaults to `(default)`
- `FIRESTORE_EMULATOR_HOST` — if set, skips ADC and uses dummy token
- `GOOGLE_APPLICATION_CREDENTIALS` — service account JSON path (consumed by googleauth)

## What you must verify / fix

### 1. **Compilation**

The code has not been run through `moon build`. Likely issues to expect:

- **MoonBit syntax pitfalls**:
  - `defer { let _ = container.cleanup() }` — confirm `defer` body is allowed to call async fns; otherwise wrap or restructure
  - `async test "..."` blocks — verify the syntax is current; in some versions it's `test "..." async { ... }`
  - `fail!` / `assert_eq!` / `assert_true!` — confirm these are valid macro names in current `moonbitlang/core/test`
  - `Result[T, E]` vs the older `Result<T, E>` — should be `[]` in modern MoonBit
  - `Map[String, Json] = {}` literal — verify this initializes an empty map; may need `Map::new()`
  - `args.contains("--readonly")` where `args : Array[String]` — confirm `Array.contains` exists; if not use `args.iter().any(fn(a) { a == "--readonly" })`

- **JSON pattern matching**: Code uses `Object(obj)`, `String(s)`, `Number(n)`, `Array(arr)`, `Null`, `True`, `False` directly as `Json` constructors. The actual variant names in `moonbitlang/core/json` may differ — check with `moon info` or by reading `core/json` mbti.

- **Closure `mut` capture**: `cmd/main/main.mbt` uses `Ref::new(api_client)` to mutate from inside a closure. If `Ref` doesn't exist in current core, use `@async.Channel` or restructure.

- **Trailing comma in array literals** in `Array([... , ...])` may not be accepted; check.

- **`String.trim_space()`**: confirm method name. May be `trim()` or `trim_chars(...)`.

- **`@core.GoogleClient::new(get_token)`**: positional vs labeled arg. Reference: `https://github.com/ryota0624/moonbit_googleapis/blob/main/sample/firestore/main.mbt` shows `@core.GoogleClient::new(fn() { token })` — confirm signature.

### 2. **Type fidelity with googleapis v0.2.2**

The wrapper assumes these signatures (verified from main HEAD on 2026-04-16):

```moonbit
// All on FirestoreService
get_document(name : String, read_time?, transaction?) -> Document
list_documents(parent, collection_id, order_by?, page_size?, page_token?, ...) -> ListDocumentsResponse
create_document(parent, collection_id, request : Document, document_id?) -> Document
delete_document(name) -> Json
run_query(parent, request : RunQueryRequest) -> Array[RunQueryResponse]
batch_get_documents(database, request : BatchGetDocumentsRequest) -> Array[BatchGetDocumentsResponse]
```

`Document` struct fields: `name : String?`, `fields : Json?`, `create_time : String?`, `update_time : String?`.

`BatchGetDocumentsResponse` fields: `found : Document?`, `missing : String?`, `read_time : String?`, `transaction : String?`.

If any of these are wrong, fix `firestore/client.mbt` accordingly.

### 3. **HttpError catch arms**

Code does:
```moonbit
catch {
  @http.HttpError::NetworkError(msg) => Err("network error: \{msg}")
  @http.HttpError::TimeoutError(msg) => Err("timeout: \{msg}")
  @http.HttpError::InvalidUrl(msg) => Err("invalid url: \{msg}")
}
```

`HttpError` is declared as `pub all suberror HttpError { NetworkError(String); TimeoutError(String); InvalidUrl(String) }`. Verify the `catch` arm syntax matches your MoonBit version — it may need to be `@http.HttpError::NetworkError(msg) => ...` or `NetworkError(msg) => ...` depending on import style.

### 4. **Emulator container**

`test/firestore_integration/emulator.mbt` spawns:

```
gcr.io/google.com/cloudsdktool/cloud-sdk:emulators
  cmd: gcloud emulators firestore start --host-port=0.0.0.0:8080 --project=test-project
  wait: TcpPort(8080), timeout 60s
```

**Verify**:
- The image+tag exists and contains `gcloud` with the firestore emulator preinstalled.
- TCP port 8080 readiness is sufficient — the emulator may accept TCP before being ready for requests. If tests are flaky, switch to `WaitStrategy::LogMessage("Dev App Server is now running")` or `LogMessage("Firestore Emulator running")`.
- Increase `with_wait_timeout` if first-time image pull is slow on the test host.

### 5. **Batch_get streaming response**

In v0.2.2, `batch_get_documents` returns `Array[BatchGetDocumentsResponse]` — one element per requested document (plus possibly transaction-only metadata responses). Implementation in `firestore/client.mbt`:

```moonbit
responses.filter_map(fn(r) {
  match r.found {
    Some(doc) => Some(BatchGetResult::Found(doc))
    None => match r.missing {
      Some(name) => Some(BatchGetResult::Missing(name))
      None => None  // skip transaction-only responses
    }
  }
})
```

The test `firestore client: batch_get multiple mixed` requests 3 docs (2 existing + 1 missing) and asserts the result has length 3, with 2 Found and 1 Missing. **If the response array contains an extra metadata entry**, this assertion will fail — adjust by filtering only entries with found-or-missing payload (already done) and confirm the final count is exactly 3.

### 6. **MCP protocol conformance**

Test requests against the MCP spec at https://spec.modelcontextprotocol.io/. Specifically:

- `initialize` response must include `protocolVersion`, `serverInfo`, `capabilities` — currently `2024-11-05`. If the version has moved on (e.g. `2025-06-18`), update.
- `tools/list` response must use `inputSchema` (camelCase) — verified.
- `tools/call` response must contain `content : [{type, text}]` array — verified.
- `notifications/initialized` (no response expected) — currently NOT handled; the loop will return `METHOD_NOT_FOUND`. **Add handling**: if `req.method_` starts with `notifications/`, skip sending a response. Important: notifications have no `id` field.

### 7. **Logging hygiene**

`@stdio.stdout` is reserved for MCP messages. `@transport.log()` writes to stderr — confirm no other code accidentally writes to stdout (e.g. via `println`). Search for `println` in the codebase and replace with `@transport.log` if any are inside the MCP loop.

## Commands to run

```bash
# 1. Resolve deps (these may not yet be published to mooncakes — see "Open questions")
moon update

# 2. Build the binary
moon build --target native cmd/main

# 3. Smoke-test the protocol (no Docker, no auth needed for these)
moon test test/firestore_integration -p "codec:" -p "mcp protocol:" -p "mcp read-only:"

# 4. Full integration tests (requires Docker daemon)
moon test test/firestore_integration

# 5. Run the server manually with the emulator
docker run -d -p 8080:8080 \
  gcr.io/google.com/cloudsdktool/cloud-sdk:emulators \
  gcloud emulators firestore start --host-port=0.0.0.0:8080 --project=test
GCP_PROJECT=test FIRESTORE_EMULATOR_HOST=localhost:8080 \
  ./target/native/release/build/cmd/main/main.exe

# In another terminal, send a request:
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | nc -q1 localhost ...
# (or pipe directly into the binary)
```

## Open questions for you to resolve

1. **mooncakes.io publication status**: The three `ryota0624/*` deps must be installable via `moon update`. If they're not on mooncakes.io yet, fall back to git submodules or a `moon.work` workspace pointing at local clones.

2. **Streaming actually works?**: Verify the integration test for `batch_get multiple mixed` actually returns 3 results from the running emulator. The Firestore REST `batchGet` is server-streaming JSON; the v0.2.2 generator was supposed to handle this. If only 1 response comes back, the generator may not have applied to `batch_get` and you'll need to either (a) decode the response body manually, or (b) file an issue against `moonbit_googleapis`.

3. **`@env.args()` package**: `moonbitlang/core/env` is imported in `cmd/main/moon.pkg`. If the actual API is different (e.g. `@env.get_args()` or `Sys.argv`), update `main.mbt` accordingly.

4. **`mizchi/x/sys` vs `moonbitlang/core/sys`**: We use `mizchi/x/sys` for `get_env_var` and `exit` because that's what `googleauth` depends on transitively. If that causes a version conflict, switch to `moonbitlang/core/sys`.

## Style/conventions to maintain

- No C FFI — use only `moonbitlang/async` for I/O.
- All MCP server output goes to stdout via `@transport.send_message`. All diagnostics go to stderr via `@transport.log`.
- Tool error responses use `ToolResultContent::Error(msg)` (rendered as `content[0].text` with `isError: true`), not JSON-RPC error responses, except for protocol-level errors (parse failure, unknown method, read-only violation).
- Subcollection paths are first-class — never assume single-segment.

## Stretch goals (after green build)

- `firestore_update_document` (uses `update_document` / `patch` semantics with `update_mask`)
- `firestore_run_aggregation_query` (count, sum, avg)
- `page_token` round-trip in `firestore_list_documents` so the client can paginate
- Service account file-path flag (`--credentials /path/to/sa.json`) overriding ADC
- README.md with Claude Desktop config example

## Deliverable

A green `moon test` run (with Docker available) and a buildable binary. Push fixes back to this directory.
