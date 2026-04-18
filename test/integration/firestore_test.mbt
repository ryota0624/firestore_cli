///|
/// Full Firestore CRUD round-trip against the Google Cloud SDK emulator.
/// Shares one emulator container across the scenario because container start
/// takes ~5 seconds.
async test "firestore emulator: create / get / list / query / delete" {
  let (container, host_port) = start_firestore_emulator()
  let fc = build_emulator_firestore_client(host_port)
  let collection = "notes"
  let run = async fn() -> Unit {
    // 1. create & get
    let fields_a : Map[String, @gfs.Value] = {
      "title": @firestore.sv("alpha"),
      "count": @firestore.iv(1L),
      "active": @firestore.bv(true),
    }
    let _ = fc.create_document(collection, doc_id="doc-a", fields_a)
    let got = fc.get_document(collection, "doc-a")
    let got_fields = got.fields.unwrap_or({})
    assert_eq(got_fields["title"].string_value, Some("alpha"))
    assert_eq(got_fields["count"].integer_value, Some("1"))
    assert_eq(got_fields["active"].boolean_value, Some(true))

    // 2. multiple creates + list
    let fields_b : Map[String, @gfs.Value] = {
      "title": @firestore.sv("beta"),
      "count": @firestore.iv(2L),
    }
    let fields_c : Map[String, @gfs.Value] = {
      "title": @firestore.sv("gamma"),
      "count": @firestore.iv(3L),
    }
    let _ = fc.create_document(collection, doc_id="doc-b", fields_b)
    let _ = fc.create_document(collection, doc_id="doc-c", fields_c)
    let list_resp = fc.list_documents(collection)
    let listed = list_resp.documents.unwrap_or([])
    assert_true(listed.length() >= 3)
    let names : Array[String] = listed
      .iter()
      .map(fn(d) { d.name.unwrap_or("") })
      .collect()
    assert_true(names.iter().any(fn(n) { n.has_suffix("/doc-a") }))
    assert_true(names.iter().any(fn(n) { n.has_suffix("/doc-b") }))
    assert_true(names.iter().any(fn(n) { n.has_suffix("/doc-c") }))

    // 3. query by field
    let hits = fc.query_collection(
      collection,
      "title",
      "EQUAL",
      @firestore.sv("beta"),
    )
    assert_eq(hits.length(), 1)
    assert_eq(hits[0].fields.unwrap()["title"].string_value, Some("beta"))

    // 4. delete + get must fail
    fc.delete_document(collection, "doc-a")
    let after = fc.list_documents(collection)
    let remaining : Array[String] = after.documents
      .unwrap_or([])
      .iter()
      .map(fn(d) { d.name.unwrap_or("") })
      .collect()
    assert_false(remaining.iter().any(fn(n) { n.has_suffix("/doc-a") }))

    // cleanup: delete the remaining docs to keep runs hermetic
    fc.delete_document(collection, "doc-b")
    fc.delete_document(collection, "doc-c")
  }
  let result : Result[Unit, Error] = Ok(run()) catch { e => Err(e) }
  let _ = container.stop()
  let _ = container.remove()
  match result {
    Ok(_) => ()
    Err(e) => raise e
  }
}
