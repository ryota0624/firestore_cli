///|
pub(open) trait FirestoreReader {
  async get_document(Self, collection_path : String, doc_id : String) -> Json
  async list_documents(
    Self,
    collection_path : String,
    page_size : Int?,
    page_token : String?,
  ) -> Json
  async query_collection(
    Self,
    collection_path : String,
    field : String,
    op : String,
    value : Json,
    limit : Int?,
  ) -> Json
}

///|
pub const PROTOCOL_VERSION : String = "2025-06-18"

///|
fn rpc_ok(response_id : Json, result : Json) -> JsonRpcResponse {
  JsonRpcResponse::{
    jsonrpc: "2.0",
    id: Some(response_id),
    result: Some(result),
    error: None,
  }
}

///|
fn rpc_error(
  response_id : Json,
  code : Int,
  message : String,
) -> JsonRpcResponse {
  JsonRpcResponse::{
    jsonrpc: "2.0",
    id: Some(response_id),
    result: None,
    error: Some(JsonRpcError::{ code, message_: message, data: None }),
  }
}

///|
fn initialize_result() -> Json {
  Json::object({
    "protocolVersion": Json::string(PROTOCOL_VERSION),
    "capabilities": Json::object({ "tools": Json::object({}) }),
    "serverInfo": Json::object({
      "name": Json::string("firestire-mcp"),
      "version": Json::string("0.1.0"),
    }),
  })
}

///|
fn tool_schemas() -> Array[Tool] {
  [
    Tool::{
      name: "firestore_get_document",
      description: "Fetch a single Firestore document by collection path and document id.",
      input_schema: Json::object({
        "type": Json::string("object"),
        "properties": Json::object({
          "collection_path": Json::object({ "type": Json::string("string") }),
          "doc_id": Json::object({ "type": Json::string("string") }),
        }),
        "required": Json::array([
          Json::string("collection_path"),
          Json::string("doc_id"),
        ]),
      }),
    },
    Tool::{
      name: "firestore_list_documents",
      description: "List documents in a collection with optional paging.",
      input_schema: Json::object({
        "type": Json::string("object"),
        "properties": Json::object({
          "collection_path": Json::object({ "type": Json::string("string") }),
          "page_size": Json::object({ "type": Json::string("integer") }),
          "page_token": Json::object({ "type": Json::string("string") }),
        }),
        "required": Json::array([Json::string("collection_path")]),
      }),
    },
    Tool::{
      name: "firestore_query_collection",
      description: "Run a structured query against a collection (single field filter).",
      input_schema: Json::object({
        "type": Json::string("object"),
        "properties": Json::object({
          "collection_path": Json::object({ "type": Json::string("string") }),
          "field": Json::object({ "type": Json::string("string") }),
          "op": Json::object({ "type": Json::string("string") }),
          "value": Json::object({}),
          "limit": Json::object({ "type": Json::string("integer") }),
        }),
        "required": Json::array([
          Json::string("collection_path"),
          Json::string("field"),
          Json::string("op"),
          Json::string("value"),
        ]),
      }),
    },
  ]
}

///|
fn tools_list_result() -> Json {
  let tools = tool_schemas().map(fn(t) { t.to_json() })
  Json::object({ "tools": Json::array(tools) })
}

///|
fn wrap_tool_result(content : ToolResultContent) -> Json {
  let is_err = match content {
    Error(_) => true
    Text(_) => false
  }
  Json::object({
    "content": Json::array([content.to_json()]),
    "isError": Json::boolean(is_err),
  })
}

///|
fn arg_obj(params : Json?) -> Result[Map[String, Json], String] {
  match params {
    None => Err("missing params")
    Some(Json::Object(o)) => Ok(o)
    Some(_) => Err("params must be a JSON object")
  }
}

///|
fn get_str(obj : Map[String, Json], key : String) -> Result[String, String] {
  match obj.get(key) {
    Some(Json::String(s)) => Ok(s)
    _ => Err("missing or invalid \{key}")
  }
}

///|
fn get_opt_str(
  obj : Map[String, Json],
  key : String,
) -> Result[String?, String] {
  match obj.get(key) {
    None | Some(Json::Null) => Ok(None)
    Some(Json::String(s)) => Ok(Some(s))
    _ => Err("invalid \{key}")
  }
}

///|
fn get_opt_int(obj : Map[String, Json], key : String) -> Result[Int?, String] {
  match obj.get(key) {
    None | Some(Json::Null) => Ok(None)
    Some(Json::Number(n, ..)) => Ok(Some(n.to_int()))
    _ => Err("invalid \{key}")
  }
}

///|
pub async fn[R : FirestoreReader] handle_request(
  req : JsonRpcRequest,
  reader : R,
) -> JsonRpcResponse? {
  if req.method_.has_prefix("notifications/") {
    return None
  }
  guard req.id is Some(rid) else { return None }
  match req.method_ {
    "initialize" => Some(rpc_ok(rid, initialize_result()))
    "tools/list" => Some(rpc_ok(rid, tools_list_result()))
    "tools/call" =>
      match dispatch_tools_call(reader, req.params) {
        Ok(j) => Some(rpc_ok(rid, j))
        Err((code, msg)) => Some(rpc_error(rid, code, msg))
      }
    _ => Some(rpc_error(rid, -32601, "Method not found"))
  }
}

///|
async fn[R : FirestoreReader] dispatch_tools_call(
  reader : R,
  params : Json?,
) -> Result[Json, (Int, String)] {
  let obj = match arg_obj(params) {
    Ok(o) => o
    Err(msg) => return Err((-32602, msg))
  }
  let name = match obj.get("name") {
    Some(Json::String(n)) => n
    _ => return Err((-32602, "Invalid params: missing name"))
  }
  let args = match obj.get("arguments") {
    Some(j) => j
    None => Json::object({})
  }
  guard args is Object(arg_map) else {
    return Err((-32602, "arguments must be a JSON object"))
  }
  match name {
    "firestore_get_document" => {
      let collection_path = match get_str(arg_map, "collection_path") {
        Ok(s) => s
        Err(e) => return Err((-32602, e))
      }
      let doc_id = match get_str(arg_map, "doc_id") {
        Ok(s) => s
        Err(e) => return Err((-32602, e))
      }
      try {
        let j = reader.get_document(collection_path, doc_id)
        Ok(wrap_tool_result(Text(j.stringify())))
      } catch {
        err => Ok(wrap_tool_result(Error(err.to_string())))
      }
    }
    "firestore_list_documents" => {
      let collection_path = match get_str(arg_map, "collection_path") {
        Ok(s) => s
        Err(e) => return Err((-32602, e))
      }
      let page_size = match get_opt_int(arg_map, "page_size") {
        Ok(o) => o
        Err(e) => return Err((-32602, e))
      }
      let page_token = match get_opt_str(arg_map, "page_token") {
        Ok(o) => o
        Err(e) => return Err((-32602, e))
      }
      try {
        let j = reader.list_documents(collection_path, page_size, page_token)
        Ok(wrap_tool_result(Text(j.stringify())))
      } catch {
        err => Ok(wrap_tool_result(Error(err.to_string())))
      }
    }
    "firestore_query_collection" => {
      let collection_path = match get_str(arg_map, "collection_path") {
        Ok(s) => s
        Err(e) => return Err((-32602, e))
      }
      let field = match get_str(arg_map, "field") {
        Ok(s) => s
        Err(e) => return Err((-32602, e))
      }
      let op = match get_str(arg_map, "op") {
        Ok(s) => s
        Err(e) => return Err((-32602, e))
      }
      let value = match arg_map.get("value") {
        Some(v) => v
        None => return Err((-32602, "missing value"))
      }
      let limit = match get_opt_int(arg_map, "limit") {
        Ok(o) => o
        Err(e) => return Err((-32602, e))
      }
      try {
        let j = reader.query_collection(
          collection_path, field, op, value, limit,
        )
        Ok(wrap_tool_result(Text(j.stringify())))
      } catch {
        err => Ok(wrap_tool_result(Error(err.to_string())))
      }
    }
    _ => Ok(wrap_tool_result(Error("unknown tool: \{name}")))
  }
}

///|
pub async fn[R : FirestoreReader] run_server(reader : R) -> Unit {
  // Reference `@async` so `moon.pkg` import is used (deny-warn clean).
  ignore(@async.now())
  while true {
    let raw : Json = recv_message() catch {
      TransportError::Eof => break
      TransportError::InvalidJson => {
        send_message(rpc_error(null, -32700, "Parse error").to_json())
        continue
      }
      err => {
        log("mcp recv_message: \{err}")
        break
      }
    }
    let req = match JsonRpcRequest::from_json(raw) {
      Ok(r) => r
      Err(_) => {
        send_message(rpc_error(null, -32600, "Invalid Request").to_json())
        continue
      }
    }
    match handle_request(req, reader) {
      None => continue
      Some(resp) => send_message(resp.to_json())
    }
  }
}
