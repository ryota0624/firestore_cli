///|
pub struct Config {
  project : String
  database : String
  emulator_host : String?
}

///|
/// 環境変数から読み出す:
/// - GCP_PROJECT or GOOGLE_CLOUD_PROJECT (必須)
/// - FIRESTORE_DATABASE (default: "(default)")
/// - FIRESTORE_EMULATOR_HOST (optional: set なら emulator モード)
/// 必須項目が無ければ Err("missing GCP_PROJECT") など。
pub fn Config::from_env() -> Result[Config, String] {
  let project = match @sys.get_env_var("GCP_PROJECT") {
    Some(value) => value
    None =>
      match @sys.get_env_var("GOOGLE_CLOUD_PROJECT") {
        Some(value) => value
        None => return Err("missing GCP_PROJECT")
      }
  }
  let database = @sys.get_env_var("FIRESTORE_DATABASE").unwrap_or("(default)")
  let emulator_host = @sys.get_env_var("FIRESTORE_EMULATOR_HOST")
  Ok(Config::{ project, database, emulator_host })
}
