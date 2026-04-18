///|
pub struct JsonRpcRequest {
  jsonrpc : String
  id : Json?
  method_ : String
  params : Json?
}

///|
pub struct JsonRpcResponse {
  jsonrpc : String
  id : Json?
  result : Json?
  error : JsonRpcError?
}

///|
pub struct JsonRpcError {
  code : Int
  message_ : String
  data : Json?
}

///|
pub struct Tool {
  name : String
  description : String
  input_schema : Json
}

///|
pub enum ToolResultContent {
  Text(String)
  Error(String)
}
