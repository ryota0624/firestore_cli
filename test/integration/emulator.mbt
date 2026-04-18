///|
pub async fn start_firestore_emulator() -> (@tc.Container, Int) {
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
pub async fn build_emulator_firestore_client(
  host_port : Int,
) -> @firestore.FirestoreClient {
  let google_client = @firestore.build_emulator_client()
  @firestore.FirestoreClient::new(
    google_client,
    "test-project",
    database="(default)",
    base_url="http://127.0.0.1:\{host_port}",
  )
}
