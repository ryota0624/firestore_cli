///|
pub fn sv(value : String) -> @gfs.Value {
  @gfs.Value::{
    null_value: None,
    boolean_value: None,
    integer_value: None,
    double_value: None,
    timestamp_value: None,
    string_value: Some(value),
    bytes_value: None,
    reference_value: None,
    geo_point_value: None,
    array_value: None,
    map_value: None,
    field_reference_value: None,
    variable_reference_value: None,
    function_value: None,
    pipeline_value: None,
  }
}

///|
pub fn iv(value : Int64) -> @gfs.Value {
  @gfs.Value::{
    null_value: None,
    boolean_value: None,
    integer_value: Some(value.to_string()),
    double_value: None,
    timestamp_value: None,
    string_value: None,
    bytes_value: None,
    reference_value: None,
    geo_point_value: None,
    array_value: None,
    map_value: None,
    field_reference_value: None,
    variable_reference_value: None,
    function_value: None,
    pipeline_value: None,
  }
}

///|
pub fn bv(value : Bool) -> @gfs.Value {
  @gfs.Value::{
    null_value: None,
    boolean_value: Some(value),
    integer_value: None,
    double_value: None,
    timestamp_value: None,
    string_value: None,
    bytes_value: None,
    reference_value: None,
    geo_point_value: None,
    array_value: None,
    map_value: None,
    field_reference_value: None,
    variable_reference_value: None,
    function_value: None,
    pipeline_value: None,
  }
}

///|
pub fn dv(value : Double) -> @gfs.Value {
  @gfs.Value::{
    null_value: None,
    boolean_value: None,
    integer_value: None,
    double_value: Some(value),
    timestamp_value: None,
    string_value: None,
    bytes_value: None,
    reference_value: None,
    geo_point_value: None,
    array_value: None,
    map_value: None,
    field_reference_value: None,
    variable_reference_value: None,
    function_value: None,
    pipeline_value: None,
  }
}

///|
pub fn nullv() -> @gfs.Value {
  @gfs.Value::{
    null_value: Some(Json::null()),
    boolean_value: None,
    integer_value: None,
    double_value: None,
    timestamp_value: None,
    string_value: None,
    bytes_value: None,
    reference_value: None,
    geo_point_value: None,
    array_value: None,
    map_value: None,
    field_reference_value: None,
    variable_reference_value: None,
    function_value: None,
    pipeline_value: None,
  }
}

///|
fn map_value_to_json(fields : Map[String, @gfs.Value]) -> Json {
  let obj : Map[String, Json] = {}
  for key, value in fields {
    obj[key] = value_to_json(value)
  }
  Json::object(obj)
}

///|
/// Value を CLI / MCP 出力用の平坦な Json に変換する。
/// 例: Value{string_value: Some("hello")} → String("hello")
///     Value{integer_value: Some("42")} → Number(42.0) もしくは String ("42" のまま) — 方針統一可
pub fn value_to_json(v : @gfs.Value) -> Json {
  match v.string_value {
    Some(s) => return Json::string(s)
    None => ()
  }
  match v.integer_value {
    Some(raw) => return Json::string(raw)
    None => ()
  }
  match v.double_value {
    Some(d) => return Json::number(d)
    None => ()
  }
  match v.boolean_value {
    Some(b) => return Json::boolean(b)
    None => ()
  }
  match v.null_value {
    Some(_) => return Json::null()
    None => ()
  }
  match v.timestamp_value {
    Some(s) => return Json::string(s)
    None => ()
  }
  match v.bytes_value {
    Some(s) => return Json::string(s)
    None => ()
  }
  match v.reference_value {
    Some(s) => return Json::string(s)
    None => ()
  }
  match v.field_reference_value {
    Some(s) => return Json::string(s)
    None => ()
  }
  match v.variable_reference_value {
    Some(s) => return Json::string(s)
    None => ()
  }
  match v.geo_point_value {
    Some(json) => return json
    None => ()
  }
  match v.array_value {
    Some(array_value) => {
      let items : Array[Json] = []
      for item in array_value.values.unwrap_or([]) {
        items.push(value_to_json(item))
      }
      return Json::array(items)
    }
    None => ()
  }
  match v.map_value {
    Some(map_value) => return map_value_to_json(map_value.fields.unwrap_or({}))
    None => ()
  }
  match v.function_value {
    Some(function_value) => return function_value.to_json()
    None => ()
  }
  match v.pipeline_value {
    Some(pipeline_value) => return pipeline_value.to_json()
    None => ()
  }
  Json::null()
}

///|
/// Json プリミティブ (null, boolean, number, string) を @gfs.Value に変換する。
/// - Json::Null → null value
/// - Json::True / Json::False → boolean value
/// - Json::Number(n) → n.to_int64().to_double() == n なら integer, そうでなければ double
/// - Json::String(s) → string value
/// - Json::Array / Json::Object → Err（現在はサポート外）
pub fn json_to_value(j : Json) -> Result[@gfs.Value, String] {
  match j {
    Json::Null => Ok(nullv())
    Json::True => Ok(bv(true))
    Json::False => Ok(bv(false))
    Json::Number(n, ..) => {
      let i = n.to_int64()
      if i.to_double() == n {
        Ok(iv(i))
      } else {
        Ok(dv(n))
      }
    }
    Json::String(s) => Ok(sv(s))
    Json::Array(_) =>
      Err("json_to_value: arrays are not supported (only primitives)")
    Json::Object(_) =>
      Err("json_to_value: objects are not supported (only primitives)")
  }
}

///|
/// Document を {name, fields, create_time, update_time} を持つ Json Object に変換する。
/// fields は Map[String, Json] として各 Value を value_to_json で変換する。
pub fn document_to_json(doc : @gfs.Document) -> Json {
  let fields_json : Map[String, Json] = {}
  for key, value in doc.fields.unwrap_or({}) {
    fields_json[key] = value_to_json(value)
  }
  Json::object({
    "name": match doc.name {
      Some(name) => Json::string(name)
      None => Json::null()
    },
    "fields": Json::object(fields_json),
    "create_time": match doc.create_time {
      Some(ts) => Json::string(ts)
      None => Json::null()
    },
    "update_time": match doc.update_time {
      Some(ts) => Json::string(ts)
      None => Json::null()
    },
  })
}
