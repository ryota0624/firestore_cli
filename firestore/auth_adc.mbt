///|
/// Auto-detect credentials (gcloud ADC / GOOGLE_APPLICATION_CREDENTIALS /
/// metadata server) and build a `GoogleClient`.
///
/// googleauth 0.2.0 の `get_access_token` は AuthorizedUser と MetadataServer の
/// トークン取得を実装済みだが、ServiceAccount はまだ未実装 (InvalidCredentials
/// "Phase 1.5 で未実装"を返す)。そのため ServiceAccount の場合のみ自前で
/// `get_access_token_with_scopes` を呼び分ける。
pub async fn build_production_client() -> Result[@gcore.GoogleClient, String] {
  let auth_client = match @googleauth.auto_detect_and_authenticate() {
    Ok(c) => c
    Err(e) => return Err("failed to detect credentials: \{describe_auth_err(e)}")
  }
  // Pre-flight: fail fast if the token refresh path is broken.
  match fetch_token(auth_client) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let get_token : async () -> String = async fn() -> String {
    match fetch_token(auth_client) {
      Ok(t) => t
      Err(e) => abort(e)
    }
  }
  Ok(@gcore.GoogleClient::new(get_token))
}

///|
/// service account JSON ファイルのパスから GoogleClient を構築する。
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
    Err(e) => return Err("failed to parse service account key: \{e}")
  }
  let gcc = @googleauth.from_service_account_credentials(creds)
  match @googleauth.get_access_token_with_scopes(gcc, [CLOUD_PLATFORM_SCOPE]) {
    Ok(_) => ()
    Err(e) =>
      return Err("failed to get access token: \{describe_cred_err(e)}")
  }
  let get_token : async () -> String = fn() -> String {
    match @googleauth.get_access_token_with_scopes(gcc, [CLOUD_PLATFORM_SCOPE]) {
      Ok(t) => t
      Err(e) => abort("service account token refresh failed: \{describe_cred_err(e)}")
    }
  }
  Ok(@gcore.GoogleClient::new(get_token))
}

///|
const CLOUD_PLATFORM_SCOPE : String = "https://www.googleapis.com/auth/cloud-platform"

///|
async fn fetch_token(
  c : @googleauth.GoogleAuthClient,
) -> Result[String, String] {
  match c.auth_type {
    ServiceAccount =>
      match c.credentials {
        Some(sa) => {
          let gcc = @googleauth.from_service_account_credentials(sa)
          match @googleauth.get_access_token_with_scopes(
            gcc,
            [CLOUD_PLATFORM_SCOPE],
          ) {
            Ok(t) => Ok(t)
            Err(e) =>
              Err("failed to get service account token: \{describe_cred_err(e)}")
          }
        }
        None => Err("GoogleAuthClient missing service_account credentials")
      }
    _ =>
      match @googleauth.get_access_token(c) {
        Ok(t) => Ok(t)
        Err(e) => Err("failed to get access token: \{describe_auth_err(e)}")
      }
  }
}

///|
fn describe_auth_err(e : @googleauth.AuthenticationError) -> String {
  match e {
    NoValidCredentials => "no valid credentials"
    MetadataServerError(m) => "metadata server: \{m}"
    InvalidCredentials(m) => "invalid credentials: \{m}"
  }
}

///|
fn describe_cred_err(e : @googleauth.ClientCredentialsError) -> String {
  match e {
    TokenExchangeFailed(m) => "token exchange failed: \{m}"
  }
}
