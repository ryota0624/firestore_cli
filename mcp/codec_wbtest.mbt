///|
test "JsonRpcRequest round-trip" {
  let raw : Json = @json.parse(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}",
  ) catch {
    _ => fail("json parse")
  }
  let req = match JsonRpcRequest::from_json(raw) {
    Ok(r) => r
    Err(_) => fail("from_json")
  }
  assert_eq(req.method_, "tools/list")
  assert_eq(req.jsonrpc, "2.0")
  guard req.id is Some(Json::Number(n, ..)) else { fail("id") }
  assert_eq(n.to_int(), 1)
}

///|
test "Tool::to_json uses inputSchema" {
  let t = Tool::{
    name: "x",
    description: "d",
    input_schema: Json::object({ "type": Json::string("object") }),
  }
  guard t.to_json() is Object(m) else { fail("object") }
  assert_true(m.get("inputSchema") is Some(_))
  assert_eq(
    m.get("inputSchema"),
    Some(Json::object({ "type": Json::string("object") })),
  )
}

///|
test "ToolResultContent::to_json text" {
  let j = ToolResultContent::Text("hi").to_json()
  guard j is Object(m) else { fail("object") }
  assert_eq(m.get("type"), Some(Json::string("text")))
  assert_eq(m.get("text"), Some(Json::string("hi")))
}
