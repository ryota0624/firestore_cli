///|
test "normalize_field_filter_op maps symbolic operators" {
  assert_eq(normalize_field_filter_op("=="), "EQUAL")
  assert_eq(normalize_field_filter_op("!="), "NOT_EQUAL")
  assert_eq(normalize_field_filter_op("<"), "LESS_THAN")
  assert_eq(normalize_field_filter_op("<="), "LESS_THAN_OR_EQUAL")
  assert_eq(normalize_field_filter_op(">"), "GREATER_THAN")
  assert_eq(normalize_field_filter_op(">="), "GREATER_THAN_OR_EQUAL")
}

///|
test "field_filter_from_shorthand uses normalized operator" {
  let flt = field_filter_from_shorthand("status", "==", Json::string("active"))
  assert_eq(flt.op, Some("EQUAL"))
  assert_eq(flt.field.unwrap().field_path, Some("status"))
  assert_eq(flt.value.unwrap().string_value, Some("active"))
}

///|
test "field_filter_from_json uses normalized operator" {
  let flt = field_filter_from_json(
    Json::object({
      "field": Json::string("status"),
      "op": Json::string(">="),
      "value": Json::number(10.0),
    }),
  )
  assert_eq(flt.op, Some("GREATER_THAN_OR_EQUAL"))
  assert_eq(flt.field.unwrap().field_path, Some("status"))
  assert_eq(flt.value.unwrap().integer_value, Some("10"))
}
