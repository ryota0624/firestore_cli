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

///|
/// service account JSON ファイルのパスから GoogleClient を構築する。
/// 読み込み失敗・パース失敗・認証失敗は Err を返す。
pub async fn build_production_client_from_service_account(
  path : String,
) -> Result[@gcore.GoogleClient, String] {
  let data = @fs.read_file(path) catch {
    _ => return Err("failed to read credentials: \{path}")
  }
  let content = data.text() catch {
    _ => return Err("failed to decode credentials: \{path}")
  }
  let creds = match @googleauth.parse_service_account_key(content) {
    Ok(c) => c
    Err(_) => return Err("failed to parse service account key: \{path}")
  }
  let auth_client = @googleauth.new_auth_client(Some(creds))
  match @googleauth.get_access_token(auth_client) {
    Ok(_) => ()
    Err(_) => return Err("failed to get access token from service account")
  }
  let get_token : async () -> String = fn() -> String {
    match @googleauth.get_access_token(auth_client) {
      Ok(token) => token
      Err(_) => abort("failed to get access token from service account")
    }
  }
  Ok(@gcore.GoogleClient::new(get_token))
}
