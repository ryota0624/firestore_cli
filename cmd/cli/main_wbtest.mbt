///|
test "format_http_error classifies firestore api messages as upstream api" {
  let e = @ghttp.HttpError::network_message(
    "FAILED_PRECONDITION: query requires an index",
  )
  assert_true(format_http_error(e).has_prefix("upstream api error:"))
}

///|
test "format_http_error classifies generic network messages as transport" {
  let e = @ghttp.HttpError::network_message("dial tcp 127.0.0.1:443: connect refused")
  assert_true(format_http_error(e).has_prefix("transport error:"))
}
