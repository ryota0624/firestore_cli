///|
test "local validation errors are invalid_argument (not network)" {
  ignore(json_to_value(Json::array([Json::number(1.0)])) catch {
    err => {
      assert_true(err.to_string().contains("invalid_argument:"))
      assert_false(err.to_string().contains("NetworkError"))
      ()
    }
  })
}

///|
test "http network message with firestore code is classified as upstream api" {
  ignore(
    map_http_error(fn() {
      raise @ghttp.HttpError::network_message(
        "INVALID_ARGUMENT: field filter is invalid",
      )
    }) catch {
      err => {
        assert_true(err.to_string().contains("upstream_api_error:"))
        ()
      }
    },
  )
}
