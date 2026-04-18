///|
pub fn JsonRpcRequest::from_json(j : Json) -> Result[JsonRpcRequest, String] {
  guard j is Object(obj) else { return Err("expected JSON object") }
  let jsonrpc = match obj.get("jsonrpc") {
    Some(Json::String(s)) => s
    _ => return Err("missing or invalid jsonrpc")
  }
  if jsonrpc != "2.0" {
    return Err("invalid jsonrpc version")
  }
  let method_ = match obj.get("method") {
    Some(Json::String(s)) => s
    _ => return Err("missing or invalid method")
  }
  let id = obj.get("id")
  let params = obj.get("params")
  Ok(JsonRpcRequest::{ jsonrpc, id, method_, params })
}

///|
pub fn JsonRpcError::to_json(self : JsonRpcError) -> Json {
  match self.data {
    Some(d) =>
      Json::object({
        "code": Json::number(self.code.to_double()),
        "message": Json::string(self.message_),
        "data": d,
      })
    None =>
      Json::object({
        "code": Json::number(self.code.to_double()),
        "message": Json::string(self.message_),
      })
  }
}

///|
pub fn JsonRpcResponse::to_json(self : JsonRpcResponse) -> Json {
  let m : Map[String, Json] = match (self.id, self.error, self.result) {
    (Some(id_val), Some(err), _) => {
      let o : Map[String, Json] = {
        "jsonrpc": Json::string(self.jsonrpc),
        "id": id_val,
        "error": err.to_json(),
      }
      o
    }
    (None, Some(err), _) => {
      let o : Map[String, Json] = {
        "jsonrpc": Json::string(self.jsonrpc),
        "error": err.to_json(),
      }
      o
    }
    (Some(id_val), None, Some(res)) => {
      let o : Map[String, Json] = {
        "jsonrpc": Json::string(self.jsonrpc),
        "id": id_val,
        "result": res,
      }
      o
    }
    (None, None, Some(res)) => {
      let o : Map[String, Json] = {
        "jsonrpc": Json::string(self.jsonrpc),
        "result": res,
      }
      o
    }
    _ => {
      let o : Map[String, Json] = { "jsonrpc": Json::string(self.jsonrpc) }
      o
    }
  }
  Json::object(m)
}

///|
pub fn Tool::to_json(self : Tool) -> Json {
  Json::object({
    "name": Json::string(self.name),
    "description": Json::string(self.description),
    "inputSchema": self.input_schema,
  })
}

///|
pub fn ToolResultContent::to_json(self : ToolResultContent) -> Json {
  match self {
    Text(s) =>
      Json::object({ "type": Json::string("text"), "text": Json::string(s) })
    Error(msg) =>
      Json::object({ "type": Json::string("text"), "text": Json::string(msg) })
  }
}
