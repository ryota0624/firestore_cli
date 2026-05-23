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

///|
fn start_firestore_emulator() -> (@tc.Container, Int) {
  let image = @tc.ContainerImage::new("google/cloud-sdk", "emulators")
    .with_exposed_port(8081)
    .with_cmd([
      "gcloud", "beta", "emulators", "firestore", "start", "--host-port=0.0.0.0:8081",
      "--project=test-project",
    ])
    .with_wait_for(@tc.WaitStrategy::HttpGet("/", 200))
    .with_wait_timeout(60)
  let container = match image.start() {
    Ok(c) => c
    Err(e) => abort("failed to start Firestore emulator: \{e}")
  }
  let host_port = match container.get_host_port(8081) {
    Some(port) => port
    None => abort("failed to resolve mapped port for Firestore emulator")
  }
  (container, host_port)
}

///|
fn build_emulator_reader(host_port : Int) -> Reader {
  let google_client = @firestore.build_emulator_client()
  let client = @firestore.FirestoreClient::new(
    google_client,
    "test-project",
    database="(default)",
    base_url="http://127.0.0.1:\{host_port}",
  )
  Reader::{ client, }
}

///|
async test "query_collection symbolic operator works against emulator" {
  let (container, host_port) = start_firestore_emulator()
  let reader = build_emulator_reader(host_port)
  let run = async fn() -> Unit {
    let _ = reader.client.create_document("items", doc_id="a", {
      "status": @firestore.sv("active"),
    })
    let _ = reader.client.create_document("items", doc_id="b", {
      "status": @firestore.sv("inactive"),
    })
    let docs = reader.query_collection({
      "collection_path": Json::string("items"),
      "field": Json::string("status"),
      "op": Json::string("=="),
      "value": Json::string("active"),
      "limit": Json::number(2.0),
    })
    guard docs is Array(arr) else { fail("expected array result") }
    assert_eq(arr.length(), 1)
    guard arr[0] is Object(doc) else { fail("expected document object") }
    guard doc.get("fields") is Some(Json::Object(fields)) else {
      fail("expected fields object")
    }
    assert_eq(fields.get("status"), Some(Json::string("active")))
    reader.client.delete_document("items", "a")
    reader.client.delete_document("items", "b")
  }
  let result : Result[Unit, Error] = Ok(run()) catch { e => Err(e) }
  let _ = container.stop()
  let _ = container.remove()
  match result {
    Ok(_) => ()
    Err(e) => raise e
  }
}
