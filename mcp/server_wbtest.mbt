///|
struct MockReader {
  batch_get_response : Json
}

///|
fn MockReader::default() -> MockReader {
  MockReader::{ batch_get_response: Json::array([]) }
}

///|
pub impl FirestoreReader for MockReader with get_document(
  _self,
  collection_path : String,
  doc_id : String,
) {
  Json::object({
    "name": Json::string(
      "projects/p/databases/(default)/documents/\{collection_path}/\{doc_id}",
    ),
  })
}

///|
pub impl FirestoreReader for MockReader with list_documents(
  _self,
  collection_path : String,
  page_size : Int?,
  page_token : String?,
) {
  ignore(collection_path)
  ignore(page_size)
  ignore(page_token)
  Json::object({ "documents": Json::array([]) })
}

///|
pub impl FirestoreReader for MockReader with query_collection(
  _self,
  collection_path : String,
  field : String,
  op : String,
  value : Json,
  limit : Int?,
) {
  ignore(collection_path)
  ignore(field)
  ignore(op)
  ignore(value)
  ignore(limit)
  Json::array([])
}

///|
pub impl FirestoreReader for MockReader with batch_get(self, doc_paths) {
  ignore(doc_paths)
  self.batch_get_response
}

///|
/// MockWriter records whether create/delete were called.
struct MockWriter {
  created : Array[(String, String?, Map[String, Json])]
  deleted : Array[(String, String)]
  // When true, all calls abort (used to assert writer is not reached).
  abort_on_call : Bool
}

///|
fn MockWriter::default() -> MockWriter {
  MockWriter::{ created: [], deleted: [], abort_on_call: false }
}

///|
fn MockWriter::aborting() -> MockWriter {
  MockWriter::{ created: [], deleted: [], abort_on_call: true }
}

///|
pub impl FirestoreWriter for MockWriter with create_document(
  self,
  collection_path,
  doc_id,
  fields,
) {
  if self.abort_on_call {
    abort("MockWriter::create_document should not be called")
  }
  self.created.push((collection_path, doc_id, fields))
  Json::object({
    "name": Json::string(
      "projects/p/databases/(default)/documents/\{collection_path}/created",
    ),
  })
}

///|
pub impl FirestoreWriter for MockWriter with delete_document(
  self,
  collection_path,
  doc_id,
) {
  if self.abort_on_call {
    abort("MockWriter::delete_document should not be called")
  }
  self.deleted.push((collection_path, doc_id))
}

///|
async test "initialize returns protocolVersion" {
  let req = JsonRpcRequest::{
    jsonrpc: "2.0",
    id: Some(Json::number(1.0)),
    method_: "initialize",
    params: Some(Json::object({})),
  }
  let r = MockReader::default()
  let w = MockWriter::default()
  let resp = match handle_request(req, r, w) {
    Some(x) => x
    None => fail("unexpected")
  }
  guard resp.result is Some(res) else { fail("unexpected") }
  guard res is Object(m) else { fail("unexpected") }
  assert_eq(m.get("protocolVersion"), Some(Json::string(PROTOCOL_VERSION)))
}

///|
async test "tools/list returns 6 tools (read + write)" {
  let req = JsonRpcRequest::{
    jsonrpc: "2.0",
    id: Some(Json::number(2.0)),
    method_: "tools/list",
    params: None,
  }
  let r = MockReader::default()
  let w = MockWriter::default()
  let resp = match handle_request(req, r, w) {
    Some(x) => x
    None => fail("unexpected")
  }
  guard resp.result is Some(res) else { fail("unexpected") }
  guard res is Object(m) else { fail("unexpected") }
  guard m.get("tools") is Some(Json::Array(tools)) else { fail("unexpected") }
  assert_eq(tools.length(), 6)
}

///|
async test "tools/call firestore_get_document dispatches" {
  let req = JsonRpcRequest::{
    jsonrpc: "2.0",
    id: Some(Json::number(3.0)),
    method_: "tools/call",
    params: Some(
      Json::object({
        "name": Json::string("firestore_get_document"),
        "arguments": Json::object({
          "collection_path": Json::string("notes"),
          "doc_id": Json::string("a"),
        }),
      }),
    ),
  }
  let r = MockReader::default()
  let w = MockWriter::default()
  let resp = match handle_request(req, r, w) {
    Some(x) => x
    None => fail("unexpected")
  }
  guard resp.result is Some(res) else { fail("unexpected") }
  let s = res.stringify()
  assert_true(s.contains("projects/p/databases/(default)/documents/notes/a"))
}

///|
async test "notifications/initialized returns no response" {
  let req = JsonRpcRequest::{
    jsonrpc: "2.0",
    id: None,
    method_: "notifications/initialized",
    params: None,
  }
  let r = MockReader::default()
  let w = MockWriter::default()
  guard handle_request(req, r, w) is None else {
    fail("expected no response for notification")
  }
}

///|
async test "unknown method returns -32601" {
  let req = JsonRpcRequest::{
    jsonrpc: "2.0",
    id: Some(Json::number(4.0)),
    method_: "foo/bar",
    params: None,
  }
  let r = MockReader::default()
  let w = MockWriter::default()
  let resp = match handle_request(req, r, w) {
    Some(x) => x
    None => fail("unexpected")
  }
  guard resp.error is Some(e) else { fail("unexpected") }
  assert_eq(e.code, -32601)
}

///|
async test "readonly tools/list omits write tools" {
  let req = JsonRpcRequest::{
    jsonrpc: "2.0",
    id: Some(Json::number(5.0)),
    method_: "tools/list",
    params: None,
  }
  let r = MockReader::default()
  let w = MockWriter::aborting()
  let resp = match handle_request(req, r, w, read_only=true) {
    Some(x) => x
    None => fail("unexpected")
  }
  guard resp.result is Some(res) else { fail("unexpected") }
  guard res is Object(m) else { fail("unexpected") }
  guard m.get("tools") is Some(Json::Array(tools)) else { fail("unexpected") }
  assert_eq(tools.length(), 4)
  let names : Array[String] = []
  for t in tools {
    guard t is Object(tm) else { fail("tool not object") }
    guard tm.get("name") is Some(Json::String(n)) else { fail("name missing") }
    names.push(n)
  }
  assert_false(names.contains("firestore_create_document"))
  assert_false(names.contains("firestore_delete_document"))
  assert_true(names.contains("firestore_batch_get"))
}

///|
async test "readonly write tools/call returns -32600" {
  let req = JsonRpcRequest::{
    jsonrpc: "2.0",
    id: Some(Json::number(6.0)),
    method_: "tools/call",
    params: Some(
      Json::object({
        "name": Json::string("firestore_create_document"),
        "arguments": Json::object({
          "collection_path": Json::string("notes"),
          "fields": Json::object({ "text": Json::string("hello") }),
        }),
      }),
    ),
  }
  let r = MockReader::default()
  // aborting writer verifies it is not reached in readonly mode.
  let w = MockWriter::aborting()
  let resp = match handle_request(req, r, w, read_only=true) {
    Some(x) => x
    None => fail("unexpected")
  }
  guard resp.error is Some(e) else { fail("expected rpc error") }
  assert_eq(e.code, -32600)
}

///|
async test "readonly delete tools/call returns -32600" {
  let req = JsonRpcRequest::{
    jsonrpc: "2.0",
    id: Some(Json::number(7.0)),
    method_: "tools/call",
    params: Some(
      Json::object({
        "name": Json::string("firestore_delete_document"),
        "arguments": Json::object({
          "collection_path": Json::string("notes"),
          "doc_id": Json::string("a"),
        }),
      }),
    ),
  }
  let r = MockReader::default()
  let w = MockWriter::aborting()
  let resp = match handle_request(req, r, w, read_only=true) {
    Some(x) => x
    None => fail("unexpected")
  }
  guard resp.error is Some(e) else { fail("expected rpc error") }
  assert_eq(e.code, -32600)
}

///|
async test "batch_get dispatches and returns reader payload" {
  let payload = Json::array([
    Json::object({
      "found": Json::object({
        "name": Json::string(
          "projects/p/databases/(default)/documents/notes/a",
        ),
      }),
    }),
    Json::object({
      "missing": Json::string(
        "projects/p/databases/(default)/documents/notes/gone",
      ),
    }),
  ])
  let r = MockReader::{ batch_get_response: payload }
  let w = MockWriter::default()
  let req = JsonRpcRequest::{
    jsonrpc: "2.0",
    id: Some(Json::number(8.0)),
    method_: "tools/call",
    params: Some(
      Json::object({
        "name": Json::string("firestore_batch_get"),
        "arguments": Json::object({
          "doc_paths": Json::array([
            Json::string("projects/p/databases/(default)/documents/notes/a"),
            Json::string("projects/p/databases/(default)/documents/notes/gone"),
          ]),
        }),
      }),
    ),
  }
  let resp = match handle_request(req, r, w) {
    Some(x) => x
    None => fail("unexpected")
  }
  guard resp.result is Some(res) else { fail("unexpected") }
  guard res is Object(m) else { fail("result not object") }
  guard m.get("content") is Some(Json::Array(arr)) else { fail("no content") }
  guard arr[0] is Object(c0) else { fail("content[0] not object") }
  guard c0.get("text") is Some(Json::String(text)) else { fail("no text") }
  let parsed = @json.parse(text) catch {
    _ => fail("text is not JSON")
  }
  assert_eq(parsed, payload)
}

///|
async test "create_document dispatches to writer" {
  let r = MockReader::default()
  let w = MockWriter::default()
  let req = JsonRpcRequest::{
    jsonrpc: "2.0",
    id: Some(Json::number(9.0)),
    method_: "tools/call",
    params: Some(
      Json::object({
        "name": Json::string("firestore_create_document"),
        "arguments": Json::object({
          "collection_path": Json::string("notes"),
          "doc_id": Json::string("my-id"),
          "fields": Json::object({
            "text": Json::string("hello"),
            "count": Json::number(3.0),
          }),
        }),
      }),
    ),
  }
  let resp = match handle_request(req, r, w) {
    Some(x) => x
    None => fail("unexpected")
  }
  guard resp.result is Some(_) else { fail("expected result") }
  let log = w.created
  assert_eq(log.length(), 1)
  let (cp, did, fields) = log[0]
  assert_eq(cp, "notes")
  assert_eq(did, Some("my-id"))
  assert_eq(fields.get("text"), Some(Json::string("hello")))
}

///|
async test "create_document without doc_id uses None" {
  let r = MockReader::default()
  let w = MockWriter::default()
  let req = JsonRpcRequest::{
    jsonrpc: "2.0",
    id: Some(Json::number(10.0)),
    method_: "tools/call",
    params: Some(
      Json::object({
        "name": Json::string("firestore_create_document"),
        "arguments": Json::object({
          "collection_path": Json::string("notes"),
          "fields": Json::object({ "text": Json::string("hi") }),
        }),
      }),
    ),
  }
  let resp = match handle_request(req, r, w) {
    Some(x) => x
    None => fail("unexpected")
  }
  guard resp.result is Some(_) else { fail("expected result") }
  let log = w.created
  assert_eq(log.length(), 1)
  let (_, did, _) = log[0]
  assert_eq(did, None)
}

///|
async test "delete_document dispatches to writer" {
  let r = MockReader::default()
  let w = MockWriter::default()
  let req = JsonRpcRequest::{
    jsonrpc: "2.0",
    id: Some(Json::number(11.0)),
    method_: "tools/call",
    params: Some(
      Json::object({
        "name": Json::string("firestore_delete_document"),
        "arguments": Json::object({
          "collection_path": Json::string("notes"),
          "doc_id": Json::string("a"),
        }),
      }),
    ),
  }
  let resp = match handle_request(req, r, w) {
    Some(x) => x
    None => fail("unexpected")
  }
  guard resp.result is Some(res) else { fail("expected result") }
  let log = w.deleted
  assert_eq(log.length(), 1)
  let (cp, did) = log[0]
  assert_eq(cp, "notes")
  assert_eq(did, "a")
  // Result content contains the deleted path.
  guard res is Object(m) else { fail("result not object") }
  guard m.get("content") is Some(Json::Array(arr)) else { fail("no content") }
  guard arr[0] is Object(c0) else { fail("content[0] not object") }
  guard c0.get("text") is Some(Json::String(text)) else { fail("no text") }
  assert_true(text.contains("notes/a"))
}
