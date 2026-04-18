///|
test "value_to_json: primitive values" {
  assert_eq(value_to_json(sv("x")), Json::string("x"))
  assert_eq(value_to_json(iv(42L)), Json::string("42"))
  assert_eq(value_to_json(bv(true)), Json::boolean(true))
  assert_eq(value_to_json(dv(1.5)), Json::number(1.5))
  assert_eq(value_to_json(nullv()), Json::null())
}

///|
test "value_to_json: map and array values" {
  let map_value = @gfs.Value::{
    null_value: None,
    boolean_value: None,
    integer_value: None,
    double_value: None,
    timestamp_value: None,
    string_value: None,
    bytes_value: None,
    reference_value: None,
    geo_point_value: None,
    array_value: None,
    map_value: Some(@gfs.MapValue::{ fields: Some({ "name": sv("alice") }) }),
    field_reference_value: None,
    variable_reference_value: None,
    function_value: None,
    pipeline_value: None,
  }
  let array_value = @gfs.Value::{
    null_value: None,
    boolean_value: None,
    integer_value: None,
    double_value: None,
    timestamp_value: None,
    string_value: None,
    bytes_value: None,
    reference_value: None,
    geo_point_value: None,
    array_value: Some(@gfs.ArrayValue::{ values: Some([sv("a"), iv(1L)]) }),
    map_value: None,
    field_reference_value: None,
    variable_reference_value: None,
    function_value: None,
    pipeline_value: None,
  }
  assert_eq(
    value_to_json(map_value),
    Json::object({ "name": Json::string("alice") }),
  )
  assert_eq(
    value_to_json(array_value),
    Json::array([Json::string("a"), Json::string("1")]),
  )
}

///|
test "document_to_json converts fields and metadata" {
  let doc = @gfs.Document::{
    name: Some("projects/p/databases/(default)/documents/users/u1"),
    fields: Some({ "name": sv("Alice"), "age": iv(10L) }),
    create_time: Some("2026-01-01T00:00:00.000000Z"),
    update_time: None,
  }
  assert_eq(
    document_to_json(doc),
    Json::object({
      "name": Json::string("projects/p/databases/(default)/documents/users/u1"),
      "fields": Json::object({
        "name": Json::string("Alice"),
        "age": Json::string("10"),
      }),
      "create_time": Json::string("2026-01-01T00:00:00.000000Z"),
      "update_time": Json::null(),
    }),
  )
}
