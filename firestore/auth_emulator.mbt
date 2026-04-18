///|
struct NoAuthHttpClient {
  inner : @ghttp.DefaultHttpClient
}

///|
pub impl @ghttp.HttpClient for NoAuthHttpClient with request(self, req) {
  let headers : Map[String, String] = {}
  for key, value in req.headers {
    if key != "Authorization" {
      headers[key] = value
    }
  }
  let req2 = @ghttp.HttpRequest::{
    url: req.url,
    method_: req.method_,
    headers,
    body: req.body,
  }
  self.inner.request(req2)
}

///|
/// emulator_host は "http://127.0.0.1:8081" のような URL。get_token は常に "dummy" を返す。
pub async fn build_emulator_client() -> @gcore.GoogleClient {
  let get_token : async () -> String = fn() -> String { "dummy" }
  let _ = get_token()
  let no_auth_client : &@ghttp.HttpClient = NoAuthHttpClient::{
    inner: @ghttp.DefaultHttpClient::new(),
  }
  @gcore.GoogleClient::new(get_token, http=Some(no_auth_client))
}
