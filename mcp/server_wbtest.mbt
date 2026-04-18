///|
struct MockReader {}

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
async test "initialize returns protocolVersion" {
  let req = JsonRpcRequest::{
    jsonrpc: "2.0",
    id: Some(Json::number(1.0)),
    method_: "initialize",
    params: Some(Json::object({})),
  }
  let r = MockReader::{  }
  let resp = match handle_request(req, r) {
    Some(x) => x
    None => fail("unexpected")
  }
  guard resp.result is Some(res) else { fail("unexpected") }
  guard res is Object(m) else { fail("unexpected") }
  assert_eq(m.get("protocolVersion"), Some(Json::string(PROTOCOL_VERSION)))
}

///|
async test "tools/list returns 3 tools" {
  let req = JsonRpcRequest::{
    jsonrpc: "2.0",
    id: Some(Json::number(2.0)),
    method_: "tools/list",
    params: None,
  }
  let r = MockReader::{  }
  let resp = match handle_request(req, r) {
    Some(x) => x
    None => fail("unexpected")
  }
  guard resp.result is Some(res) else { fail("unexpected") }
  guard res is Object(m) else { fail("unexpected") }
  guard m.get("tools") is Some(Json::Array(tools)) else { fail("unexpected") }
  assert_eq(tools.length(), 3)
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
  let r = MockReader::{  }
  let resp = match handle_request(req, r) {
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
  let r = MockReader::{  }
  guard handle_request(req, r) is None else {
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
  let r = MockReader::{  }
  let resp = match handle_request(req, r) {
    Some(x) => x
    None => fail("unexpected")
  }
  guard resp.error is Some(e) else { fail("unexpected") }
  assert_eq(e.code, -32601)
}
