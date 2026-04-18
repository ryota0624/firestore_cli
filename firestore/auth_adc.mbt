///|
/// googleauth の auto_detect_and_authenticate → get_access_token で得たトークンを
/// @gcore.GoogleClient::new(fn() { token }) に渡す。失敗時は Err。
pub async fn build_production_client() -> Result[@gcore.GoogleClient, String] {
  let auth_client = match @googleauth.auto_detect_and_authenticate() {
    Ok(client) => client
    Err(_) => return Err("failed to detect credentials")
  }
  match @googleauth.get_access_token(auth_client) {
    Ok(_) => ()
    Err(_) => return Err("failed to get access token")
  }
  let get_token : async () -> String = fn() -> String {
    match @googleauth.get_access_token(auth_client) {
      Ok(token) => token
      Err(_) => abort("failed to get access token")
    }
  }
  Ok(@gcore.GoogleClient::new(get_token))
}
