///|
fn restore_env_var(key : String, value : String?) -> Unit {
  match value {
    Some(v) => @sys.set_env_var(key, v)
    None => @sys.unset_env_var(key)
  }
}

///|
fn sample_service_account_json() -> String {
  (
    #|{
    #|  "type": "service_account",
    #|  "project_id": "dummy-project",
    #|  "private_key_id": "dummy-key-id",
    #|  "private_key": "-----BEGIN PRIVATE KEY-----\nDUMMY\n-----END PRIVATE KEY-----\n",
    #|  "client_email": "dummy@dummy-project.iam.gserviceaccount.com",
    #|  "client_id": "12345678901234567890",
    #|  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    #|  "token_uri": "https://oauth2.googleapis.com/token",
    #|  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
    #|  "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/dummy"
    #|}
  )
}

///|
async test "adc_login_hint: no valid credentials has login hint" {
  let old_google = @sys.get_env_var("GOOGLE_APPLICATION_CREDENTIALS")
  let old_home = @sys.get_env_var("HOME")
  let old_appdata = @sys.get_env_var("APPDATA")
  @sys.unset_env_var("GOOGLE_APPLICATION_CREDENTIALS")
  @sys.set_env_var("HOME", "/tmp/firestore-cli-auth-adc-wbtest-home")
  @sys.set_env_var("APPDATA", "/tmp/firestore-cli-auth-adc-wbtest-appdata")
  let result = @googleauth.auto_detect_and_authenticate()
  restore_env_var("GOOGLE_APPLICATION_CREDENTIALS", old_google)
  restore_env_var("HOME", old_home)
  restore_env_var("APPDATA", old_appdata)
  match result {
    Err(e) => {
      guard e is NoValidCredentials else { fail("expected NoValidCredentials") }
      let hint = adc_login_hint(e)
      guard hint is Some(h) else { fail("expected adc login hint") }
      assert_true(h.contains("gcloud auth application-default login"))
    }
    Ok(_) => fail("expected auto_detect_and_authenticate to fail")
  }
}

///|
async test "adc_login_hint: invalid credentials has login hint" {
  let creds = match
    @googleauth.parse_service_account_key(sample_service_account_json()) {
    Ok(c) => c
    Err(e) => fail("failed to parse service account test fixture: \{e}")
  }
  let auth_client = @googleauth.new_auth_client(Some(creds))
  match @googleauth.get_access_token(auth_client) {
    Err(e) => {
      guard e is InvalidCredentials(_) else {
        fail("expected InvalidCredentials")
      }
      assert_true(adc_login_hint(e) is Some(_))
    }
    Ok(_) => fail("expected get_access_token to fail for service account path")
  }
}

///|
async test "adc_login_hint: metadata server error has no login hint" {
  let auth_client = @googleauth.new_auth_client(None)
  match @googleauth.get_access_token(auth_client) {
    Err(e) => {
      guard e is MetadataServerError(_) else {
        fail("expected MetadataServerError")
      }
      assert_eq(adc_login_hint(e), None)
    }
    Ok(_) => fail("expected metadata server token request to fail")
  }
}
