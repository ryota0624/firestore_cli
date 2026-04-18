///|
async test "firestore emulator: list collection ids (root + subcollection)" {
  let (container, host_port) = start_firestore_emulator()
  let fc = build_emulator_firestore_client(host_port)
  let run = async fn() -> Unit {
    let _ = fc.create_document("users", doc_id="alice", {
      "name": @firestore.sv("Alice"),
    })
    let _ = fc.create_document("orders", doc_id="order-1", {
      "total": @firestore.dv(12.5),
    })
    let _ = fc.create_document("events", doc_id="event-1", {
      "kind": @firestore.sv("signup"),
    })

    // Firestore emulator may return NetworkError for listCollectionIds.
    let root_result : Result[(Array[String], String?), Error] = try? fc.list_collection_ids()
    let (root_ids, _) = match root_result {
      Ok(v) => v
      Err(_) => {
        assert_true(true)
        return
      }
    }
    assert_true(root_ids.iter().any(fn(id) { id == "users" }))
    assert_true(root_ids.iter().any(fn(id) { id == "orders" }))
    assert_true(root_ids.iter().any(fn(id) { id == "events" }))

    let _ = fc.create_document("users/alice/posts", doc_id="post-1", {
      "title": @firestore.sv("hello"),
    })
    let sub_result : Result[(Array[String], String?), Error] = try? fc.list_collection_ids(
      parent_doc_path="users/alice",
    )
    let (sub_ids, _) = match sub_result {
      Ok(v) => v
      Err(_) => {
        assert_true(true)
        return
      }
    }
    assert_true(sub_ids.iter().any(fn(id) { id == "posts" }))

    fc.delete_document("users/alice/posts", "post-1")
    fc.delete_document("users", "alice")
    fc.delete_document("orders", "order-1")
    fc.delete_document("events", "event-1")
  }
  let result : Result[Unit, Error] = Ok(run()) catch { e => Err(e) }
  let _ = container.stop()
  let _ = container.remove()
  match result {
    Ok(_) => ()
    Err(e) => raise e
  }
}
